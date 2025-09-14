#!/bin/bash
set -e

# cleanup.sh - Clean up old containers and images to free disk space
# Keeps a configurable number of recent images and removes dangling resources
# DRY_RUN : shows what would happen without actually making any changes


echo "🧹 Starting cleanup process..."

# Environment variables with defaults
APP_NAME=${APP_NAME:-"my-app"}
KEEP_IMAGES=${KEEP_IMAGES:-"3"}
CI_REGISTRY_IMAGE=${CI_REGISTRY_IMAGE:-""}
DRY_RUN=${DRY_RUN:-"false"}	

# Configuration
CLEANUP_LOG="/tmp/cleanup-$(date +%s).log"

# Function to log with timestamps
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message"
    echo "$message" >> "$CLEANUP_LOG"
}

# Function to log section headers
log_section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔧 $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to execute command with dry run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would execute: $cmd ($description)"
    else
        log "Executing: $description"
        if eval "$cmd"; then
            log "✅ Success: $description"
        else
            log "⚠️  Warning: Failed to $description"
        fi
    fi
}

# Check disk space before cleanup
check_disk_space_before() {
    log_section "DISK SPACE - BEFORE CLEANUP"
    
    log "Current disk usage:"
    df -h / | head -2
    
    log "Docker system disk usage:"
    docker system df 2>/dev/null || log "Unable to get Docker disk usage"
}

# Clean up stopped containers
cleanup_stopped_containers() {
    log_section "STOPPED CONTAINERS CLEANUP"
    
    local stopped_containers
    stopped_containers=$(docker ps -aq -f status=exited 2>/dev/null || true)
    
    if [[ -n "$stopped_containers" ]]; then
        log "Found $(echo "$stopped_containers" | wc -l) stopped containers"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would remove stopped containers:"
            docker ps -a -f status=exited --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null || true
        else
            log "Removing stopped containers..."
            echo "$stopped_containers" | xargs -r docker rm
            log "✅ Stopped containers removed"
        fi
    else
        log "ℹ️  No stopped containers to remove"
    fi
}

# Clean up old images for the current project
cleanup_old_images() {
    log_section "OLD IMAGES CLEANUP"
    
    if [[ -z "$CI_REGISTRY_IMAGE" ]]; then
        log "⚠️  CI_REGISTRY_IMAGE not set, skipping old image cleanup"
        return 0
    fi
    
    log "Keeping $KEEP_IMAGES most recent images for $CI_REGISTRY_IMAGE"
    
    # Get all tags for the current image, sorted by creation time
    local image_list
    image_list=$(docker images "$CI_REGISTRY_IMAGE" --format "{{.Tag}} {{.ID}} {{.CreatedAt}}" 2>/dev/null | 
                 grep -v '<none>' | 
                 sort -k3 -r || true)
    
    if [[ -z "$image_list" ]]; then
        log "ℹ️  No images found for $CI_REGISTRY_IMAGE"
        return 0
    fi
    
    local total_images
    total_images=$(echo "$image_list" | wc -l)
    log "Found $total_images images for $CI_REGISTRY_IMAGE"
    
    if [[ $total_images -le $KEEP_IMAGES ]]; then
        log "ℹ️  Only $total_images images found, keeping all (threshold: $KEEP_IMAGES)"
        return 0
    fi
    
    # Get images to remove (skip the most recent KEEP_IMAGES)
    local images_to_remove
    images_to_remove=$(echo "$image_list" | tail -n +$((KEEP_IMAGES + 1)) | awk '{print $2}')
    
    if [[ -n "$images_to_remove" ]]; then
        local remove_count
        remove_count=$(echo "$images_to_remove" | wc -l)
        log "Will remove $remove_count old images"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would remove these images:"
            echo "$image_list" | tail -n +$((KEEP_IMAGES + 1)) | while read -r line; do
                log "  $line"
            done
        else
            echo "$images_to_remove" | while read -r image_id; do
                if [[ -n "$image_id" ]]; then
                    execute_command "docker rmi $image_id" "remove image $image_id"
                fi
            done
        fi
    else
        log "ℹ️  No old images to remove"
    fi
}

# Clean up dangling images
cleanup_dangling_images() {
    log_section "DANGLING IMAGES CLEANUP"
    
    local dangling_images
    dangling_images=$(docker images -f "dangling=true" -q 2>/dev/null || true)
    
    if [[ -n "$dangling_images" ]]; then
        local count
        count=$(echo "$dangling_images" | wc -l)
        log "Found $count dangling images"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would remove dangling images:"
            docker images -f "dangling=true" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" 2>/dev/null || true
        else
            execute_command "echo '$dangling_images' | xargs -r docker rmi" "remove dangling images"
        fi
    else
        log "ℹ️  No dangling images found"
    fi
}

# Clean up unused networks
cleanup_unused_networks() {
    log_section "UNUSED NETWORKS CLEANUP"
    
    local unused_networks
    unused_networks=$(docker network ls --filter "dangling=true" -q 2>/dev/null || true)
    
    if [[ -n "$unused_networks" ]]; then
        local count
        count=$(echo "$unused_networks" | wc -l)
        log "Found $count unused networks"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would remove unused networks:"
            docker network ls --filter "dangling=true" --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" 2>/dev/null || true
        else
            execute_command "docker network prune -f" "remove unused networks"
        fi
    else
        log "ℹ️  No unused networks found"
    fi
}

# Clean up unused volumes (with caution)
cleanup_unused_volumes() {
    log_section "UNUSED VOLUMES CLEANUP"
    
    local unused_volumes
    unused_volumes=$(docker volume ls --filter "dangling=true" -q 2>/dev/null || true)
    
    if [[ -n "$unused_volumes" ]]; then
        local count
        count=$(echo "$unused_volumes" | wc -l)
        log "Found $count unused volumes"
        
        log "⚠️  Volume cleanup is conservative - only removing clearly unused volumes"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would remove unused volumes:"
            docker volume ls --filter "dangling=true" --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}" 2>/dev/null || true
        else
            # Only remove volumes that are clearly safe to remove
            execute_command "docker volume prune -f" "remove unused volumes"
        fi
    else
        log "ℹ️  No unused volumes found"
    fi
}

# Build cache cleanup
cleanup_build_cache() {
    log_section "BUILD CACHE CLEANUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would run docker builder prune"
        docker system df 2>/dev/null || true
    else
        log "Cleaning Docker build cache..."
        execute_command "docker builder prune -f" "clean build cache"
    fi
}

# System-wide cleanup
system_cleanup() {
    log_section "SYSTEM CLEANUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would run docker system prune"
    else
        log "Running system-wide cleanup (keeping volumes)..."
        execute_command "docker system prune -f" "system cleanup"
    fi
}

# Check disk space after cleanup
check_disk_space_after() {
    log_section "DISK SPACE - AFTER CLEANUP"
    
    log "Disk usage after cleanup:"
    df -h / | head -2
    
    log "Docker system disk usage after cleanup:"
    docker system df 2>/dev/null || log "Unable to get Docker disk usage"
}

# Generate cleanup summary
generate_cleanup_summary() {
    log_section "🎉 CLEANUP SUMMARY"
    
    cat << EOF
┌─────────────────────────────────────────────────────────────────┐
│                      CLEANUP COMPLETE                          │
├─────────────────────────────────────────────────────────────────┤
│ 🧹 Cleanup mode: $([ "$DRY_RUN" == "true" ] && echo "DRY RUN" || echo "EXECUTED")
│ 📦 App images kept: $KEEP_IMAGES most recent
│ 📋 Log file: $CLEANUP_LOG
│ ⏰ Completed: $(date)
├─────────────────────────────────────────────────────────────────┤
│                    CLEANUP ACTIONS                             │
├─────────────────────────────────────────────────────────────────┤
│ ✅ Stopped containers removed
│ ✅ Old images cleaned (keeping $KEEP_IMAGES)
│ ✅ Dangling images removed
│ ✅ Unused networks removed
│ ✅ Unused volumes removed (conservative)
│ ✅ Build cache cleaned
│ ✅ System cleanup performed
└─────────────────────────────────────────────────────────────────┘
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        log "💡 To execute cleanup, run: DRY_RUN=false $0"
    fi
}

# Main cleanup function
main() {
    log "🧹 Starting cleanup for $APP_NAME..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "🔍 Running in DRY RUN mode - no changes will be made"
    fi
    
    # Pre-cleanup assessment
    check_disk_space_before
    
    # Cleanup operations
    cleanup_stopped_containers
    cleanup_old_images
    cleanup_dangling_images
    cleanup_unused_networks
    cleanup_unused_volumes
    cleanup_build_cache
    system_cleanup
    
    # Post-cleanup assessment
    check_disk_space_after
    generate_cleanup_summary
    
    log "✅ Cleanup completed successfully!"
}

# Error handling
trap 'log "❌ Cleanup script failed at line $LINENO"' ERR

# Execute main function
main "$@"
