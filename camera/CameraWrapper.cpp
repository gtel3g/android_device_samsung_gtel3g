/*
 * T561 / gtel3g legacy camera HAL1 wrapper
 *
 * Android 9-facing module:
 *     camera.sc8830.so
 *
 * Wrapped stock Samsung/SPRD module:
 *     camera.vendor.sc8830.so
 *
 * V0 intentionally does not modify CameraParameters or buffers.
 * Its only job is to bridge/proxy HAL1 calls and provide useful logs.
 */

#define LOG_NDEBUG 0
#define LOG_TAG "T561_CAMWRAP"

#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <hardware/camera.h>
#include <hardware/hardware.h>
#include <log/log.h>
#include <utils/Timers.h>

static pthread_mutex_t gVendorModuleLock = PTHREAD_MUTEX_INITIALIZER;
static camera_module_t *gVendorModule = NULL;

typedef struct wrapper_camera_device {
    camera_device_t base;
    camera_device_t *vendor;

    int id;
    int released;

    camera_notify_callback notify_cb;
    camera_data_callback data_cb;
    camera_data_timestamp_callback data_cb_timestamp;
    camera_request_memory get_memory;
    void *framework_user;

    unsigned int notify_count;
    unsigned int data_count;
    unsigned int timestamp_count;
} wrapper_camera_device_t;

static inline wrapper_camera_device_t *wrapper_from_device(camera_device_t *device)
{
    return reinterpret_cast<wrapper_camera_device_t *>(device);
}

static inline const wrapper_camera_device_t *wrapper_from_device_const(
        const camera_device_t *device)
{
    return reinterpret_cast<const wrapper_camera_device_t *>(device);
}

static int check_vendor_module()
{
    if (gVendorModule != NULL)
        return 0;

    pthread_mutex_lock(&gVendorModuleLock);

    if (gVendorModule == NULL) {
        const hw_module_t *module = NULL;

        ALOGI("loading stock HAL: camera.vendor.<ro.hardware>.so");

        int ret = hw_get_module_by_class(
                CAMERA_HARDWARE_MODULE_ID, "vendor", &module);

        if (ret != 0 || module == NULL) {
            ALOGE("failed to load stock camera vendor HAL: ret=%d module=%p",
                  ret, module);
            pthread_mutex_unlock(&gVendorModuleLock);
            return ret != 0 ? ret : -ENODEV;
        }

        gVendorModule = reinterpret_cast<camera_module_t *>(
                const_cast<hw_module_t *>(module));

        ALOGI("stock HAL loaded: name='%s' author='%s' module_api=0x%04x",
              gVendorModule->common.name ? gVendorModule->common.name : "(null)",
              gVendorModule->common.author ? gVendorModule->common.author : "(null)",
              gVendorModule->common.module_api_version);
    }

    pthread_mutex_unlock(&gVendorModuleLock);
    return 0;
}

static bool valid_device(camera_device_t *device, const char *func)
{
    if (device == NULL) {
        ALOGE("%s: wrapper device is NULL", func);
        return false;
    }

    wrapper_camera_device_t *w = wrapper_from_device(device);

    if (w->vendor == NULL || w->vendor->ops == NULL) {
        ALOGE("%s: vendor device/ops is NULL, id=%d", func, w->id);
        return false;
    }

    return true;
}

/********************************************************************
 * Callback bridge
 ********************************************************************/

static void wrapper_notify_cb(
        int32_t msg_type, int32_t ext1, int32_t ext2, void *user)
{
    wrapper_camera_device_t *w =
            reinterpret_cast<wrapper_camera_device_t *>(user);

    if (w == NULL || w->notify_cb == NULL)
        return;

    if (w->notify_count++ < 8) {
        ALOGI("cb notify id=%d type=0x%x ext1=%d ext2=%d",
              w->id, msg_type, ext1, ext2);
    }

    w->notify_cb(msg_type, ext1, ext2, w->framework_user);
}

static void wrapper_data_cb(
        int32_t msg_type,
        const camera_memory_t *data,
        unsigned int index,
        camera_frame_metadata_t *metadata,
        void *user)
{
    wrapper_camera_device_t *w =
            reinterpret_cast<wrapper_camera_device_t *>(user);

    if (w == NULL || w->data_cb == NULL)
        return;

    if (w->data_count++ < 8) {
        ALOGI("cb data id=%d type=0x%x index=%u data=%p metadata=%p",
              w->id, msg_type, index, data, metadata);
    }

    w->data_cb(msg_type, data, index, metadata, w->framework_user);
}

static void wrapper_data_cb_timestamp(
        nsecs_t timestamp,
        int32_t msg_type,
        const camera_memory_t *data,
        unsigned int index,
        void *user)
{
    wrapper_camera_device_t *w =
            reinterpret_cast<wrapper_camera_device_t *>(user);

    if (w == NULL || w->data_cb_timestamp == NULL)
        return;

    if (w->timestamp_count++ < 8) {
        ALOGI("cb timestamp id=%d type=0x%x index=%u ts=%lld data=%p",
              w->id, msg_type, index,
              static_cast<long long>(timestamp), data);
    }

    w->data_cb_timestamp(
            timestamp, msg_type, data, index, w->framework_user);
}

static camera_memory_t *wrapper_get_memory(
        int fd, size_t buf_size, unsigned int num_bufs, void *user)
{
    wrapper_camera_device_t *w =
            reinterpret_cast<wrapper_camera_device_t *>(user);

    if (w == NULL || w->get_memory == NULL) {
        ALOGE("get_memory: callback missing");
        return NULL;
    }

    ALOGV("get_memory id=%d fd=%d size=%zu count=%u",
          w->id, fd, buf_size, num_bufs);

    return w->get_memory(fd, buf_size, num_bufs, w->framework_user);
}

/********************************************************************
 * camera_device_ops_t bridge
 ********************************************************************/

static int camera_set_preview_window(
        camera_device_t *device, preview_stream_ops_t *window)
{
    if (!valid_device(device, __func__))
        return -EINVAL;

    wrapper_camera_device_t *w = wrapper_from_device(device);
    ALOGI("set_preview_window id=%d window=%p", w->id, window);

    if (w->vendor->ops->set_preview_window == NULL)
        return -ENOSYS;

    int ret = w->vendor->ops->set_preview_window(w->vendor, window);
    ALOGI("set_preview_window id=%d ret=%d", w->id, ret);
    return ret;
}

static void camera_set_callbacks(
        camera_device_t *device,
        camera_notify_callback notify_cb,
        camera_data_callback data_cb,
        camera_data_timestamp_callback data_cb_timestamp,
        camera_request_memory get_memory,
        void *user)
{
    if (!valid_device(device, __func__))
        return;

    wrapper_camera_device_t *w = wrapper_from_device(device);

    w->notify_cb = notify_cb;
    w->data_cb = data_cb;
    w->data_cb_timestamp = data_cb_timestamp;
    w->get_memory = get_memory;
    w->framework_user = user;

    w->notify_count = 0;
    w->data_count = 0;
    w->timestamp_count = 0;

    ALOGI("set_callbacks id=%d framework_user=%p", w->id, user);

    if (w->vendor->ops->set_callbacks != NULL) {
        /*
         * Important: the vendor HAL receives 'w' as its callback user.
         * Our callbacks translate that back to framework_user.
         */
        w->vendor->ops->set_callbacks(
                w->vendor,
                wrapper_notify_cb,
                wrapper_data_cb,
                wrapper_data_cb_timestamp,
                wrapper_get_memory,
                w);
    }
}

static void camera_enable_msg_type(camera_device_t *device, int32_t msg_type)
{
    if (!valid_device(device, __func__))
        return;

    wrapper_camera_device_t *w = wrapper_from_device(device);
    ALOGV("enable_msg_type id=%d type=0x%x", w->id, msg_type);

    if (w->vendor->ops->enable_msg_type != NULL)
        w->vendor->ops->enable_msg_type(w->vendor, msg_type);
}

static void camera_disable_msg_type(camera_device_t *device, int32_t msg_type)
{
    if (!valid_device(device, __func__))
        return;

    wrapper_camera_device_t *w = wrapper_from_device(device);
    ALOGV("disable_msg_type id=%d type=0x%x", w->id, msg_type);

    if (w->vendor->ops->disable_msg_type != NULL)
        w->vendor->ops->disable_msg_type(w->vendor, msg_type);
}

static int camera_msg_type_enabled(camera_device_t *device, int32_t msg_type)
{
    if (!valid_device(device, __func__))
        return 0;

    wrapper_camera_device_t *w = wrapper_from_device(device);

    if (w->vendor->ops->msg_type_enabled == NULL)
        return 0;

    return w->vendor->ops->msg_type_enabled(w->vendor, msg_type);
}

static int camera_start_preview(camera_device_t *device)
{
    if (!valid_device(device, __func__))
        return -EINVAL;

    wrapper_camera_device_t *w = wrapper_from_device(device);
    ALOGI("start_preview id=%d", w->id);

    if (w->vendor->ops->start_preview == NULL)
        return -ENOSYS;

    int ret = w->vendor->ops->start_preview(w->vendor);
    ALOGI("start_preview id=%d ret=%d", w->id, ret);
    return ret;
}

static void camera_stop_preview(camera_device_t *device)
{
    if (!valid_device(device, __func__))
        return;

    wrapper_camera_device_t *w = wrapper_from_device(device);
    ALOGI("stop_preview id=%d", w->id);

    if (w->vendor->ops->stop_preview != NULL)
        w->vendor->ops->stop_preview(w->vendor);
}

static int camera_preview_enabled(camera_device_t *device)
{
    if (!valid_device(device, __func__))
        return 0;

    wrapper_camera_device_t *w = wrapper_from_device(device);

    if (w->vendor->ops->preview_enabled == NULL)
        return 0;

    return w->vendor->ops->preview_enabled(w->vendor);
}

static int camera_store_meta_data_in_buffers(
        camera_device_t *device, int enable)
{
    if (!valid_device(device, __func__))
        return -EINVAL;

    wrapper_camera_device_t *w = wrapper_from_device(device);
    ALOGI("store_meta_data_in_buffers id=%d enable=%d", w->id, enable);

    if (w->vendor->ops->store_meta_data_in_buffers == NULL)
        return -ENOSYS;

    int ret =
        w->vendor->ops->store_meta_data_in_buffers(w->vendor, enable);

    ALOGI("store_meta_data_in_buffers id=%d ret=%d", w->id, ret);
    return ret;
}

static int camera_start_recording(camera_device_t *device)
{
    if (!valid_device(device, __func__))
        return -EINVAL;

    wrapper_camera_device_t *w = wrapper_from_device(device);
    ALOGI("start_recording id=%d", w->id);

    if (w->vendor->ops->start_recording == NULL)
        return -ENOSYS;

    int ret = w->vendor->ops->start_recording(w->vendor);
    ALOGI("start_recording id=%d ret=%d", w->id, ret);
    return ret;
}

static void camera_stop_recording(camera_device_t *device)
{
    if (!valid_device(device, __func__))
        return;

    wrapper_camera_device_t *w = wrapper_from_device(device);
    ALOGI("stop_recording id=%d", w->id);

    if (w->vendor->ops->stop_recording != NULL)
        w->vendor->ops->stop_recording(w->vendor);
}

static int camera_recording_enabled(camera_device_t *device)
{
    if (!valid_device(device, __func__))
        return 0;

    wrapper_camera_device_t *w = wrapper_from_device(device);

    if (w->vendor->ops->recording_enabled == NULL)
        return 0;

    return w->vendor->ops->recording_enabled(w->vendor);
}

static void camera_release_recording_frame(
        camera_device_t *device, const void *opaque)
{
    if (!valid_device(device, __func__))
        return;

    wrapper_camera_device_t *w = wrapper_from_device(device);

    if (w->vendor->ops->release_recording_frame != NULL)
        w->vendor->ops->release_recording_frame(w->vendor, opaque);
}

static int camera_auto_focus(camera_device_t *device)
{
    if (!valid_device(device, __func__))
        return -EINVAL;

    wrapper_camera_device_t *w = wrapper_from_device(device);
    ALOGI("auto_focus id=%d", w->id);

    if (w->vendor->ops->auto_focus == NULL)
        return -ENOSYS;

    int ret = w->vendor->ops->auto_focus(w->vendor);
    ALOGI("auto_focus id=%d ret=%d", w->id, ret);
    return ret;
}

static int camera_cancel_auto_focus(camera_device_t *device)
{
    if (!valid_device(device, __func__))
        return -EINVAL;

    wrapper_camera_device_t *w = wrapper_from_device(device);
    ALOGI("cancel_auto_focus id=%d", w->id);

    if (w->vendor->ops->cancel_auto_focus == NULL)
        return -ENOSYS;

    int ret = w->vendor->ops->cancel_auto_focus(w->vendor);
    ALOGI("cancel_auto_focus id=%d ret=%d", w->id, ret);
    return ret;
}

static int camera_take_picture(camera_device_t *device)
{
    if (!valid_device(device, __func__))
        return -EINVAL;

    wrapper_camera_device_t *w = wrapper_from_device(device);
    ALOGI("take_picture id=%d", w->id);

    if (w->vendor->ops->take_picture == NULL)
        return -ENOSYS;

    int ret = w->vendor->ops->take_picture(w->vendor);
    ALOGI("take_picture id=%d ret=%d", w->id, ret);
    return ret;
}

static int camera_cancel_picture(camera_device_t *device)
{
    if (!valid_device(device, __func__))
        return -EINVAL;

    wrapper_camera_device_t *w = wrapper_from_device(device);
    ALOGI("cancel_picture id=%d", w->id);

    if (w->vendor->ops->cancel_picture == NULL)
        return -ENOSYS;

    int ret = w->vendor->ops->cancel_picture(w->vendor);
    ALOGI("cancel_picture id=%d ret=%d", w->id, ret);
    return ret;
}

static int camera_set_parameters(
        camera_device_t *device, const char *params)
{
    if (!valid_device(device, __func__))
        return -EINVAL;

    wrapper_camera_device_t *w = wrapper_from_device(device);

    ALOGI("set_parameters id=%d len=%zu",
          w->id, params ? strlen(params) : 0u);

    if (w->vendor->ops->set_parameters == NULL)
        return -ENOSYS;

    /*
     * V0: pass the parameter string through unchanged.
     */
    int ret = w->vendor->ops->set_parameters(w->vendor, params);
    ALOGI("set_parameters id=%d ret=%d", w->id, ret);
    return ret;
}

static char *camera_get_parameters(camera_device_t *device)
{
    if (!valid_device(device, __func__))
        return NULL;

    wrapper_camera_device_t *w = wrapper_from_device(device);

    if (w->vendor->ops->get_parameters == NULL)
        return NULL;

    /*
     * V0: return the vendor-owned parameter block unchanged.
     * camera_put_parameters() below returns it to the same vendor HAL.
     */
    char *params = w->vendor->ops->get_parameters(w->vendor);

    ALOGI("get_parameters id=%d ptr=%p len=%zu",
          w->id, params, params ? strlen(params) : 0u);

    return params;
}

static void camera_put_parameters(
        camera_device_t *device, char *params)
{
    if (!valid_device(device, __func__))
        return;

    wrapper_camera_device_t *w = wrapper_from_device(device);

    ALOGV("put_parameters id=%d ptr=%p", w->id, params);

    if (w->vendor->ops->put_parameters != NULL)
        w->vendor->ops->put_parameters(w->vendor, params);
}

static int camera_send_command(
        camera_device_t *device, int32_t cmd, int32_t arg1, int32_t arg2)
{
    if (!valid_device(device, __func__))
        return -EINVAL;

    wrapper_camera_device_t *w = wrapper_from_device(device);

    ALOGI("send_command id=%d cmd=%d arg1=%d arg2=%d",
          w->id, cmd, arg1, arg2);

    if (w->vendor->ops->send_command == NULL)
        return -ENOSYS;

    int ret = w->vendor->ops->send_command(
            w->vendor, cmd, arg1, arg2);

    ALOGI("send_command id=%d cmd=%d ret=%d", w->id, cmd, ret);
    return ret;
}

static void camera_release(camera_device_t *device)
{
    if (!valid_device(device, __func__))
        return;

    wrapper_camera_device_t *w = wrapper_from_device(device);

    if (w->released) {
        ALOGW("release id=%d already released", w->id);
        return;
    }

    ALOGI("release id=%d", w->id);

    if (w->vendor->ops->release != NULL)
        w->vendor->ops->release(w->vendor);

    w->released = 1;
}

static int camera_dump(camera_device_t *device, int fd)
{
    if (!valid_device(device, __func__))
        return -EINVAL;

    wrapper_camera_device_t *w = wrapper_from_device(device);

    if (w->vendor->ops->dump == NULL)
        return 0;

    return w->vendor->ops->dump(w->vendor, fd);
}

static camera_device_ops_t gWrapperCameraOps = {
    .set_preview_window = camera_set_preview_window,
    .set_callbacks = camera_set_callbacks,
    .enable_msg_type = camera_enable_msg_type,
    .disable_msg_type = camera_disable_msg_type,
    .msg_type_enabled = camera_msg_type_enabled,
    .start_preview = camera_start_preview,
    .stop_preview = camera_stop_preview,
    .preview_enabled = camera_preview_enabled,
    .store_meta_data_in_buffers = camera_store_meta_data_in_buffers,
    .start_recording = camera_start_recording,
    .stop_recording = camera_stop_recording,
    .recording_enabled = camera_recording_enabled,
    .release_recording_frame = camera_release_recording_frame,
    .auto_focus = camera_auto_focus,
    .cancel_auto_focus = camera_cancel_auto_focus,
    .take_picture = camera_take_picture,
    .cancel_picture = camera_cancel_picture,
    .set_parameters = camera_set_parameters,
    .get_parameters = camera_get_parameters,
    .put_parameters = camera_put_parameters,
    .send_command = camera_send_command,
    .release = camera_release,
    .dump = camera_dump,
};

/********************************************************************
 * Device/module bridge
 ********************************************************************/

static int camera_device_close(hw_device_t *device)
{
    if (device == NULL)
        return -EINVAL;

    wrapper_camera_device_t *w =
            reinterpret_cast<wrapper_camera_device_t *>(device);

    ALOGI("close id=%d wrapper=%p vendor=%p released=%d",
          w->id, w, w->vendor, w->released);

    int ret = 0;

    /*
     * Do not synthesize vendor->ops->release() here.
     * Preserve framework/vendor HAL lifetime semantics exactly.
     */
    if (w->vendor != NULL && w->vendor->common.close != NULL)
        ret = w->vendor->common.close(&w->vendor->common);

    free(w);
    return ret;
}

static int camera_device_open(
        const hw_module_t *module,
        const char *name,
        hw_device_t **device)
{
    if (module == NULL || name == NULL || device == NULL)
        return -EINVAL;

    *device = NULL;

    int ret = check_vendor_module();
    if (ret != 0)
        return ret;

    if (gVendorModule->common.methods == NULL ||
        gVendorModule->common.methods->open == NULL) {
        ALOGE("stock HAL has no module open() method");
        return -ENOSYS;
    }

    ALOGI("open request id='%s'", name);

    hw_device_t *vendor_hw_device = NULL;

    ret = gVendorModule->common.methods->open(
            &gVendorModule->common, name, &vendor_hw_device);

    if (ret != 0 || vendor_hw_device == NULL) {
        ALOGE("stock open('%s') failed ret=%d device=%p",
              name, ret, vendor_hw_device);
        return ret != 0 ? ret : -ENODEV;
    }

    camera_device_t *vendor_device =
            reinterpret_cast<camera_device_t *>(vendor_hw_device);

    if (vendor_device->ops == NULL) {
        ALOGE("stock open('%s') returned device without ops", name);
        if (vendor_hw_device->close != NULL)
            vendor_hw_device->close(vendor_hw_device);
        return -ENODEV;
    }

    wrapper_camera_device_t *w =
            reinterpret_cast<wrapper_camera_device_t *>(
                    calloc(1, sizeof(wrapper_camera_device_t)));

    if (w == NULL) {
        if (vendor_hw_device->close != NULL)
            vendor_hw_device->close(vendor_hw_device);
        return -ENOMEM;
    }

    w->id = atoi(name);
    w->vendor = vendor_device;
    w->released = 0;

    w->base.common.tag = HARDWARE_DEVICE_TAG;
    w->base.common.version = vendor_device->common.version;
    w->base.common.module = const_cast<hw_module_t *>(module);
    w->base.common.close = camera_device_close;
    w->base.ops = &gWrapperCameraOps;
    w->base.priv = NULL;

    *device = &w->base.common;

    ALOGI("open id=%d OK wrapper=%p vendor=%p vendor_dev_api=0x%04x",
          w->id, w, vendor_device, vendor_device->common.version);

    return 0;
}

static int camera_get_number_of_cameras()
{
    int ret = check_vendor_module();
    if (ret != 0)
        return 0;

    if (gVendorModule->get_number_of_cameras == NULL) {
        ALOGE("stock HAL has no get_number_of_cameras()");
        return 0;
    }

    int count = gVendorModule->get_number_of_cameras();
    ALOGI("get_number_of_cameras -> %d", count);
    return count;
}

static int camera_get_camera_info(int camera_id, camera_info *info)
{
    if (info == NULL)
        return -EINVAL;

    int ret = check_vendor_module();
    if (ret != 0)
        return ret;

    if (gVendorModule->get_camera_info == NULL) {
        ALOGE("stock HAL has no get_camera_info()");
        return -ENOSYS;
    }

    memset(info, 0, sizeof(*info));

    ret = gVendorModule->get_camera_info(camera_id, info);

    if (ret == 0) {
        ALOGI("get_camera_info id=%d facing=%d orientation=%d",
              camera_id, info->facing, info->orientation);
    } else {
        ALOGE("get_camera_info id=%d ret=%d", camera_id, ret);
    }

    return ret;
}

static hw_module_methods_t gCameraModuleMethods = {
    .open = camera_device_open,
};

extern "C" camera_module_t HAL_MODULE_INFO_SYM = {
    .common = {
        .tag = HARDWARE_MODULE_TAG,
        .module_api_version = CAMERA_MODULE_API_VERSION_1_0,
        .hal_api_version = HARDWARE_HAL_API_VERSION,
        .id = CAMERA_HARDWARE_MODULE_ID,
        .name = "Samsung T561 SC8830 Camera HAL1 Wrapper",
        .author = "T561 LineageOS port",
        .methods = &gCameraModuleMethods,
        .dso = NULL,
        .reserved = {0},
    },
    .get_number_of_cameras = camera_get_number_of_cameras,
    .get_camera_info = camera_get_camera_info,
};
