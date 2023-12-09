#include <zephyr/drivers/dac.h>
#include <zephyr/drivers/adc.h>
#include <zephyr/kernel.h>
#include <zephyr/ztest.h>
#include <stdio.h>

#if DT_NODE_HAS_PROP(DT_PATH(zephyr_user), answer)

#define ANSWER DT_PROP(DT_PATH(zephyr_user), answer)

#endif

#if DT_NODE_HAS_PROP(DT_PATH(zephyr_user), dac) 
#define DAC_DEVICE_NODE		DT_PROP(DT_PATH(zephyr_user), dac)// DT_NODELABEL(dac0)

static const struct dac_channel_cfg dac_ch_cfg = {
	.channel_id = DT_PROP(DT_PATH(zephyr_user), dac_channel_id),
	.resolution = DT_PROP(DT_PATH(zephyr_user), dac_resolution),
	.buffered = true
};

static const struct device *init_dac(void)
{
	int ret;
	const struct device *const dac_dev = DEVICE_DT_GET(DAC_DEVICE_NODE);

	zassert_true(device_is_ready(dac_dev), "DAC device is not ready");

	ret = dac_channel_setup(dac_dev, &dac_ch_cfg);
	zassert_equal(ret, 0,
		"Setting up of the first channel failed with code %d", ret);

	return dac_dev;
}
#endif

#define PASSES 5
#define DIV 2
#define ADC_DEVICE_NODE DT_PHANDLE(DT_PATH(zephyr_user), io_channels)


#define CHANNEL UTIL_CAT(channel_, DT_PHA(DT_PATH(zephyr_user), io_channels, input))

static const struct adc_channel_cfg adc_ch_cfg = ADC_CHANNEL_CFG_DT(DT_CHILD(ADC_DEVICE_NODE, CHANNEL));


static const struct device *init_adc(void)
{
	int ret;
	const struct device *const adc_dev = DEVICE_DT_GET(ADC_DEVICE_NODE);

	zassert_true(device_is_ready(adc_dev), "ADC device is not ready");
	ret = adc_channel_setup(adc_dev, &adc_ch_cfg);
	zassert_equal(ret, 0,
		"Setting up of the ADC channel failed with code %d", ret);
	
	return adc_dev;
}


static int test_dac_to_adc(void)
{
	int ret, write_val;
	
	const struct device *adc_dev = init_adc();	
	if (!adc_dev) {
		return TC_FAIL;
	}
	
	
	const struct device *dac_dev = init_dac();
	if (!dac_dev) {
		return TC_FAIL;
	}

	write_val = (1U << dac_ch_cfg.resolution) / DIV;

	ret = dac_write_value(dac_dev, DT_PROP(DT_PATH(zephyr_user), dac_channel_id), write_val); 	

	zassert_equal(ret, 0, "dac_write_value() failed with code %d", ret);

	k_sleep(K_MSEC(10));

	static int32_t m_sample_buffer[1];
	struct adc_sequence sequence = {
		.channels    = BIT(adc_ch_cfg.channel_id),
		.buffer      = &m_sample_buffer,
		.buffer_size = sizeof(m_sample_buffer),
		.resolution  = DT_PROP(DT_CHILD(ADC_DEVICE_NODE, CHANNEL), zephyr_resolution),
		};

	ret = adc_read(adc_dev, &sequence);
	
   	float val_mv = m_sample_buffer[0]; 
	
	val_mv  = (val_mv/4096 * 3.3); 


	printk("\n");
	printk("ADC VOLTAGE: %.3f\n", val_mv);
	printk("\n");

	zassert_equal(ret, 0, "adc_read() failed with code %d", ret);
	zassert_within(m_sample_buffer[0],
		(1U << DT_PROP(DT_CHILD(ADC_DEVICE_NODE, CHANNEL), zephyr_resolution)) / DIV, 32,
		"Value %d read from ADC does not match expected range.",
		m_sample_buffer[0]);
	
	
	return TC_PASS;
}

ZTEST(dac_adc_loop, test_dac_to_adc)
{
	int i;
	for (i = 0; i < PASSES; i++){
		zassert_true(test_dac_to_adc() == TC_PASS);
	}
}

ZTEST_SUITE(dac_adc_loop, NULL, NULL, NULL, NULL, NULL);
