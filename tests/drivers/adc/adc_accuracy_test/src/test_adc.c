#include <zephyr/drivers/dac.h>
#include <zephyr/drivers/adc.h>
#include <zephyr/kernel.h>
#include <zephyr/ztest.h>
#include <stdio.h>

#define PASSES 5
#define DIV 2
#define ADC_DEVICE_NODE DT_PHANDLE(DT_PATH(zephyr_user), io_channels)

#if DT_NODE_HAS_PROP(DT_PATH(zephyr_user), reference)
#define REF_V DT_PROP(DT_PATH(zephyr_user), reference)
#endif

#if DT_NODE_HAS_PROP(DT_PATH(zephyr_user), dac) 
#define DAC_DEVICE_NODE	DT_PROP(DT_PATH(zephyr_user), dac)
#endif

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

#ifdef DAC_DEVICE_NODE

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

static int test_dac_to_adc(void)
{
	int ret, write_val;
	
	const struct device *adc_dev = init_adc();	
	const struct device *dac_dev = init_dac();

	if (!adc_dev || !dac_dev) {
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

	printf ("VAL_MV: %f\n", val_mv);	
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

ZTEST(adc_accuracy_test, test_dac_to_adc)
{
	int i;
	for (i = 0; i < PASSES; i++){
		zassert_true(test_dac_to_adc() == TC_PASS);
	}
}

ZTEST_SUITE(adc_accuracy_test, NULL, NULL, NULL, NULL, NULL);
#endif

#ifdef REF_V
static int test_ref_to_adc(void)
{
	int ret;
	float exp_val;

	exp_val = ((float)REF_V/3300) * 4096;

	const struct device *adc_dev = init_adc();	
	if (!adc_dev) {
		return TC_FAIL;
	}

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

	printk("\nADC VOLTAGE: %.3f\n", val_mv);\
	
	zassert_equal(ret, 0, "adc_read() failed with code %d", ret);
	zassert_within(m_sample_buffer[0],
		(exp_val), 32,
		"Value %.3fV read from ADC does not match expected range (%.3fV).", val_mv, (float)REF_V/1000);
	
	
	return TC_PASS;
}

ZTEST(adc_accuracy_test, test_ref_to_adc)
{
	zassert_true(test_ref_to_adc() == TC_PASS);
}
ZTEST_SUITE(adc_accuracy_test, NULL, NULL, NULL, NULL, NULL);

#endif

