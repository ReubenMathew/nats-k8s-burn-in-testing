# This file contains helper functions and it is sourced by the main script.

function publish_local_source_image()
{
    local source_dir="$1"

    test -d "${source_dir}" || fail "Not found: ${source_dir}"

    # Build the image
    echo "🌱  Building server image from source: ${source_dir}"
    docker build -t "${IMAGE_NAME}:${LOCAL_IMAGE_TAG}" -f "${DOCKERFILE}" "${source_dir}" || fail "Failed to build image"

    # Push the image to the local registry
    docker push "${REGISTRY}/${IMAGE_NAME}:${LOCAL_IMAGE_TAG}" || fail "Failed to push image"
}

function publish_latest_release_image()
{
    # Pull the image from Docker Hub
    echo "📦  Pulling latest release image from Docker Hub: ${IMAGE_NAME}:${UPSTREAM_IMAGE_TAG}"
    docker pull "${IMAGE_NAME}:${UPSTREAM_IMAGE_TAG}" || fail "Failed to pull release image"

    # Tag the image
    docker tag "${IMAGE_NAME}:${UPSTREAM_IMAGE_TAG}" "${REGISTRY}/${IMAGE_NAME}:${LOCAL_IMAGE_TAG}" || fail "Failed to tag image"

    # Push the image to the local registry
    docker push "${REGISTRY}/${IMAGE_NAME}:${LOCAL_IMAGE_TAG}" || fail "Failed to push image"
}
