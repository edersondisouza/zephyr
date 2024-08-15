#define DT_DRV_COMPAT aardvark_i2c_flash_controller
#define AARDVARK_I2C_FLASH_CONTROLLER_NODE DT_INST(0, aardvark_i2c_flash_controller)
#define SOC_NV_FLASH_NODE DT_CHILD(AARDVARK_I2C_FLASH_CONTROLLER_NODE, flash_0)

#include <zephyr/drivers/flash.h>
#include <zephyr/drivers/i2c.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(flash_i2c_aardvark, CONFIG_FLASH_LOG_LEVEL);

#define I2C_ADDR	0x20
#define I2C_WAIT_USEC	1000 * 5

static uint8_t data_buf[64];
static uint8_t write_data[16];

static const struct flash_parameters flash_i2c_aardvark_parameters = {
	.write_block_size = DT_PROP(SOC_NV_FLASH_NODE, write_block_size),
	.erase_value = 0xff,
};

static const struct device *const i2c_bus = DEVICE_DT_GET(DT_PHANDLE(AARDVARK_I2C_FLASH_CONTROLLER_NODE, device));
static size_t fa_size;

static void aardvark_get_size(const struct device *dev, uint32_t *size)
{
	write_data[0] = 0x01;
	i2c_write(i2c_bus, (uint8_t *)&write_data, 1, I2C_ADDR);
	k_busy_wait(I2C_WAIT_USEC);
	i2c_read(i2c_bus, (uint8_t *)&data_buf, 4, I2C_ADDR);
	*size = data_buf[0] << 24 | data_buf[1] << 16 | data_buf[2] << 8 | data_buf[3];
}

static int aardvark_read(const struct device *dev, uint8_t *buf, size_t buf_len,
			 uint32_t addr, uint8_t len)
{
	int ret;

	if (len > 64 || buf_len < len) {
		return -EINVAL;
	}

	write_data[0] = 0x02;
	write_data[1] = (addr >> 24) & 0xFF;
	write_data[2] = (addr >> 16) & 0xFF;
	write_data[3] = (addr >> 8) & 0xFF;
	write_data[4] = addr & 0xFF;

	write_data[5] = len;

	i2c_write(i2c_bus, (uint8_t *)&write_data, 6, I2C_ADDR);

	k_busy_wait(I2C_WAIT_USEC);
	ret = i2c_read(i2c_bus, data_buf, len, I2C_ADDR);

	/* On esp32s3, I can't just i2c_read directly into buf if it's
	 * in IRAM, as IRAM access needs 4-byte alignment. Hence, the memcpy
	 * below. */
	memcpy(buf, data_buf, len);

	return 0;
}

static int flash_i2c_aardvark_read(const struct device *dev, off_t address,
				   void *buffer, size_t length)
{
	ARG_UNUSED(dev);
	size_t to_read;
	uint8_t *dst = buffer;

	if (address < 0 || (address + length > fa_size)) {
		return -EINVAL;
	}

	while (length > 0) {
		to_read = MIN(length, 64);
		aardvark_read(i2c_bus, dst, length, address, to_read);
		dst += to_read;
		address += to_read;
		length -= to_read;
		k_busy_wait(I2C_WAIT_USEC);
	}

	return 0;
}

static int flash_i2c_aardvark_write(const struct device *dev, off_t address,
				    const void *data, size_t length)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(address);
	ARG_UNUSED(data);
	ARG_UNUSED(length);

	return -ENOTSUP;
}

static const struct flash_parameters *flash_i2c_aardvark_get_parameters(
	const struct device *dev)
{
	ARG_UNUSED(dev);

	return &flash_i2c_aardvark_parameters;
}

#if CONFIG_FLASH_PAGE_LAYOUT
static const struct flash_pages_layout flash_i2c_aardvark_pages_layout = {
	.pages_count = DT_REG_SIZE(SOC_NV_FLASH_NODE) / DT_PROP(SOC_NV_FLASH_NODE, erase_block_size),
	.pages_size = DT_PROP(SOC_NV_FLASH_NODE, erase_block_size),
};

void flash_i2c_aardvark_page_layout(const struct device *dev,
			     const struct flash_pages_layout **layout,
			     size_t *layout_size)
{
	*layout = &flash_i2c_aardvark_pages_layout;
	*layout_size = 1;
}
#endif /* CONFIG_FLASH_PAGE_LAYOUT */

static int flash_i2c_aardvark_init(const struct device *dev)
{
	ARG_UNUSED(dev);

	aardvark_get_size(i2c_bus, &fa_size);

	return 0;
}

static const struct flash_driver_api flash_i2c_aardvark_api = {
	.read = flash_i2c_aardvark_read,
	.write = flash_i2c_aardvark_write,
	.get_parameters = flash_i2c_aardvark_get_parameters,
#ifdef CONFIG_FLASH_PAGE_LAYOUT
	.page_layout = flash_i2c_aardvark_page_layout,
#endif
};

DEVICE_DT_INST_DEFINE(0, flash_i2c_aardvark_init, NULL, NULL, NULL, POST_KERNEL,
		      CONFIG_FLASH_AARDVARK_I2C_INIT_PRIORITY,
		      &flash_i2c_aardvark_api);
