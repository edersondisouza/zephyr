/*
 * Copyright (c) 2022 Nordic Semiconductor ASA
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file
 * @brief USB host controller (UHC) driver API
 */

#ifndef ZEPHYR_INCLUDE_UHC_H
#define ZEPHYR_INCLUDE_UHC_H

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/net/buf.h>
#include <zephyr/usb/usb_ch9.h>
#include <zephyr/sys/dlist.h>

/**
 * @brief USB host controller (UHC) driver API
 * @defgroup uhc_api USB host controller driver API
 * @since 3.3.0
 * @ingroup io_interfaces
 * @{
 */

/**
 * UHC endpoint buffer info
 *
 * This structure is mandatory for all UHC request.
 * It contains the meta data about the request and FIFOs
 * to store net_buf structures for each request.
 *
 * The members of this structure should not be used
 * directly by a higher layer (host stack).
 */
struct uhc_transfer {
	/** dlist node */
	sys_dnode_t node;
	/** FIFO requests to process */
	struct k_fifo queue;
	/** FIFO to keep completed requests */
	struct k_fifo done;
	/** Device (peripheral) address */
	uint8_t addr;
	/** Endpoint to which request is associated */
	uint8_t ep;
	/** Endpoint attributes (TBD) */
	uint8_t attrib;
	/** Maximum packet size */
	uint16_t mps;
	/** Timeout in number of frames */
	uint16_t timeout;
	/** Flag marks request buffer claimed by the controller */
	unsigned int claimed : 1;
	/** Flag marks request buffer is queued */
	unsigned int queued : 1;
	/** Flag marks setup stage of transfer */
	unsigned int setup : 1;
	/** Transfer owner */
	void *owner;
};

/**
 * @brief USB host controller event types
 */
enum uhc_event_type {
	/** Low speed device connected */
	UHC_EVT_DEV_CONNECTED_LS,
	/** Full speed device connected */
	UHC_EVT_DEV_CONNECTED_FS,
	/** High speed device connected */
	UHC_EVT_DEV_CONNECTED_HS,
	/** Device (peripheral) removed */
	UHC_EVT_DEV_REMOVED,
	/** Bus reset operation finished */
	UHC_EVT_RESETED,
	/** Bus suspend operation finished */
	UHC_EVT_SUSPENDED,
	/** Bus resume operation finished */
	UHC_EVT_RESUMED,
	/** Remote wakeup signal */
	UHC_EVT_RWUP,
	/** Endpoint request result event */
	UHC_EVT_EP_REQUEST,
	/**
	 * Non-correctable error event, requires attention from higher
	 * levels or application.
	 */
	UHC_EVT_ERROR,
};

/**
 * USB host controller event
 *
 * Common structure for all events that originate from
 * the UHC driver and are passed to higher layer using
 * message queue and a callback (uhc_event_cb_t) provided
 * by higher layer during controller initialization (uhc_init).
 */
struct uhc_event {
	/** slist node for the message queue */
	sys_snode_t node;
	/** Event type */
	enum uhc_event_type type;
	union {
		/** Event value */
		uint32_t value;
		/** Pointer to request used only for UHC_EVT_EP_REQUEST */
		struct uhc_transfer *xfer;
	};
	/** Event status, 0 on success, other (transfer) values on error */
	int status;
	/** Pointer to controller's device struct */
	const struct device *dev;
};

/**
 * @typedef uhc_event_cb_t
 * @brief Callback to submit UHC event to higher layer.
 *
 * At the higher level, the event is to be inserted into a message queue.
 *
 * @param[in] dev      Pointer to device struct of the driver instance
 * @param[in] event    Point to event structure
 *
 * @return 0 on success, all other values should be treated as error.
 */
typedef int (*uhc_event_cb_t)(const struct device *dev,
			      const struct uhc_event *const event);

/**
 * USB host controller capabilities
 *
 * This structure is mainly intended for the USB host stack.
 */
struct uhc_device_caps {
	/** USB high speed capable controller */
	uint32_t hs : 1;
};

/**
 * Controller is initialized by uhc_init()
 */
#define UHC_STATUS_INITIALIZED		0
/**
 * Controller is enabled and all API functions are available
 */
#define UHC_STATUS_ENABLED		1

/**
 * Common UHC driver data structure
 *
 * Mandatory structure for each UHC controller driver.
 * To be implemented as device's private data (device->data).
 */
struct uhc_data {
	/** Controller capabilities */
	struct uhc_device_caps caps;
	/** Driver access mutex */
	struct k_mutex mutex;
	/** dlist for control transfers */
	sys_dlist_t ctrl_xfers;
	/** dlist for bulk transfers */
	sys_dlist_t bulk_xfers;
	/** Callback to submit an UHC event to upper layer */
	uhc_event_cb_t event_cb;
	/** USB host controller status */
	atomic_t status;
	/** Driver private data */
	void *priv;
};

/**
 * @brief Checks whether the controller is initialized.
 *
 * @param[in] dev      Pointer to device struct of the driver instance
 *
 * @return true if controller is initialized, false otherwise
 */
static inline bool uhc_is_initialized(const struct device *dev)
{
	struct uhc_data *data = dev->data;

	return atomic_test_bit(&data->status, UHC_STATUS_INITIALIZED);
}

/**
 * @brief Checks whether the controller is enabled.
 *
 * @param[in] dev      Pointer to device struct of the driver instance
 *
 * @return true if controller is enabled, false otherwise
 */
static inline bool uhc_is_enabled(const struct device *dev)
{
	struct uhc_data *data = dev->data;

	return atomic_test_bit(&data->status, UHC_STATUS_ENABLED);
}

/**
 * @cond INTERNAL_HIDDEN
 */
struct uhc_api {
	int (*lock)(const struct device *dev);
	int (*unlock)(const struct device *dev);

	int (*init)(const struct device *dev);
	int (*enable)(const struct device *dev);
	int (*disable)(const struct device *dev);
	int (*shutdown)(const struct device *dev);

	int (*bus_reset)(const struct device *dev);
	int (*sof_enable)(const struct device *dev);
	int (*bus_suspend)(const struct device *dev);
	int (*bus_resume)(const struct device *dev);

	int (*ep_enqueue)(const struct device *dev,
			  struct uhc_transfer *const xfer);
	int (*ep_dequeue)(const struct device *dev,
			  struct uhc_transfer *const xfer);
};
/**
 * @endcond
 */

/**
 * @brief Reset USB bus
 *
 * Perform USB bus reset, controller may emit UHC_EVT_RESETED
 * at the end of reset signaling.
 *
 * @param[in] dev      Pointer to device struct of the driver instance
 *
 * @return 0 on success, all other values should be treated as error.
 * @retval -EBUSY if the controller is already performing a bus operation
 */
static inline int uhc_bus_reset(const struct device *dev)
{
	const struct uhc_api *api = dev->api;
	int ret;

	api->lock(dev);
	ret = api->bus_reset(dev);
	api->unlock(dev);

	return ret;
}

/**
 * @brief Enable Start of Frame generator
 *
 * Enable SOF generator.
 *
 * @param[in] dev      Pointer to device struct of the driver instance
 *
 * @return 0 on success, all other values should be treated as error.
 * @retval -EALREADY if already enabled
 */
static inline int uhc_sof_enable(const struct device *dev)
{
	const struct uhc_api *api = dev->api;
	int ret;

	api->lock(dev);
	ret = api->sof_enable(dev);
	api->unlock(dev);

	return ret;
}

/**
 * @brief Suspend USB bus
 *
 * Disable SOF generator and emit UHC_EVT_SUSPENDED event when USB bus
 * is suspended.
 *
 * @param[in] dev      Pointer to device struct of the driver instance
 *
 * @return 0 on success, all other values should be treated as error.
 * @retval -EALREADY if already suspended
 */
static inline int uhc_bus_suspend(const struct device *dev)
{
	const struct uhc_api *api = dev->api;
	int ret;

	api->lock(dev);
	ret = api->bus_suspend(dev);
	api->unlock(dev);

	return ret;
}

/**
 * @brief Resume USB bus
 *
 * Signal resume for at least 20ms, emit UHC_EVT_RESUMED at the end of USB
 * bus resume signaling. The SoF generator should subsequently start within 3ms.
 *
 * @param[in] dev      Pointer to device struct of the driver instance
 *
 * @return 0 on success, all other values should be treated as error.
 * @retval -EBUSY if the controller is already performing a bus operation
 */
static inline int uhc_bus_resume(const struct device *dev)
{
	const struct uhc_api *api = dev->api;
	int ret;

	api->lock(dev);
	ret = api->bus_resume(dev);
	api->unlock(dev);

	return ret;
}

/**
 * @brief Allocate UHC transfer
 *
 * Allocate a new transfer from common transfer pool.
 * Transfer has no buffers after allocation, these can be
 * requested and assigned separately.
 *
 * @param[in] dev     Pointer to device struct of the driver instance
 * @param[in] addr    Device (peripheral) address
 * @param[in] ep      Endpoint address
 * @param[in] attrib  Endpoint attributes
 * @param[in] mps     Maximum packet size of the endpoint
 * @param[in] timeout Timeout in number of frames
 * @param[in] owner   Transfer owner
 *
 * @return pointer to allocated transfer or NULL on error.
 */
struct uhc_transfer *uhc_xfer_alloc(const struct device *dev,
				    const uint8_t addr,
				    const uint8_t ep,
				    const uint8_t attrib,
				    const uint16_t mps,
				    const uint16_t timeout,
				    void *const owner);

/**
 * @brief Free UHC transfer and any buffers
 *
 * Free any buffers and put the transfer back into the transfer pool.
 *
 * @param[in] dev    Pointer to device struct of the driver instance
 * @param[in] xfer   Pointer to UHC transfer
 *
 * @return 0 on success, all other values should be treated as error.
 */
int uhc_xfer_free(const struct device *dev,
		  struct uhc_transfer *const xfer);

/**
 * @brief Allocate UHC transfer buffer
 *
 * Allocate a new buffer from common request buffer pool and
 * assign it to the transfer.
 *
 * @param[in] dev    Pointer to device struct of the driver instance
 * @param[in] xfer   Pointer to UHC transfer
 * @param[in] size   Size of the request buffer
 *
 * @return pointer to allocated request or NULL on error.
 */
struct net_buf *uhc_xfer_buf_alloc(const struct device *dev,
				   struct uhc_transfer *const xfer,
				   const size_t size);

/**
 * @brief Free UHC request buffer
 *
 * Put the buffer back into the request buffer pool.
 *
 * @param[in] dev    Pointer to device struct of the driver instance
 * @param[in] buf    Pointer to UHC request buffer
 *
 * @return 0 on success, all other values should be treated as error.
 */
int uhc_xfer_buf_free(const struct device *dev, struct net_buf *const buf);

/**
 * @brief Queue USB host controller transfer
 *
 * Add transfer to the queue. If the queue is empty, the transfer
 * can be claimed by the controller immediately.
 *
 * @param[in] dev    Pointer to device struct of the driver instance
 * @param[in] xfer   Pointer to UHC transfer
 *
 * @return 0 on success, all other values should be treated as error.
 * @retval -EPERM controller is not initialized
 */
int uhc_ep_enqueue(const struct device *dev, struct uhc_transfer *const xfer);

/**
 * @brief Remove a USB host controller transfers from queue
 *
 * Not implemented yet.
 *
 * @param[in] dev    Pointer to device struct of the driver instance
 * @param[in] xfer   Pointer to UHC transfer
 *
 * @return 0 on success, all other values should be treated as error.
 * @retval -EPERM controller is not initialized
 */
int uhc_ep_dequeue(const struct device *dev, struct uhc_transfer *const xfer);

/**
 * @brief Initialize USB host controller
 *
 * Initialize USB host controller.
 *
 * @param[in] dev      Pointer to device struct of the driver instance
 * @param[in] event_cb Event callback from the higher layer (USB host stack)
 *
 * @return 0 on success, all other values should be treated as error.
 * @retval -EINVAL on parameter error (no callback is passed)
 * @retval -EALREADY already initialized
 */
int uhc_init(const struct device *dev, uhc_event_cb_t event_cb);

/**
 * @brief Enable USB host controller
 *
 * Enable powered USB host controller and allow host stack to
 * recognize and enumerate devices.
 *
 * @param[in] dev    Pointer to device struct of the driver instance
 *
 * @return 0 on success, all other values should be treated as error.
 * @retval -EPERM controller is not initialized
 * @retval -EALREADY already enabled
 */
int uhc_enable(const struct device *dev);

/**
 * @brief Disable USB host controller
 *
 * Disable enabled USB host controller.
 *
 * @param[in] dev    Pointer to device struct of the driver instance
 *
 * @return 0 on success, all other values should be treated as error.
 * @retval -EALREADY already disabled
 */
int uhc_disable(const struct device *dev);

/**
 * @brief Poweroff USB host controller
 *
 * Shut down the controller completely to reduce energy consumption
 * or to change the role of the controller.
 *
 * @param[in] dev    Pointer to device struct of the driver instance
 *
 * @return 0 on success, all other values should be treated as error.
 * @retval -EALREADY controller is already uninitialized
 */
int uhc_shutdown(const struct device *dev);

/**
 * @brief Get USB host controller capabilities
 *
 * Obtain the capabilities of the controller
 * such as high speed (HS), and more.
 *
 * @param[in] dev    Pointer to device struct of the driver instance
 *
 * @return USB host controller capabilities.
 */
static inline struct uhc_device_caps uhc_caps(const struct device *dev)
{
	struct uhc_data *data = dev->data;

	return data->caps;
}

/**
 * @}
 */

#endif /* ZEPHYR_INCLUDE_UHC_H */
