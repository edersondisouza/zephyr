#include <zephyr/drivers/dac.h>
#include <zephyr/drivers/adc.h>
#include <zephyr/kernel.h>
#include <zephyr/ztest.h>
#include <stdio.h>

/*#if defined(CONFIG_BOARD_FRDM_K64F)

#define DAC_DEVICE_NODE		DT_NODELABEL(dac0)
#define DAC_RESOLUTION		12
#define DAC_CHANNEL_ID		0

#define ADC_DEVICE_NODE		DT_NODELABEL(adc0)
#define ADC_RESOLUTION		12
#define ADC_GAIN		ADC_GAIN_1
#define ADC_REFERENCE		ADC_REF_INTERNAL
#define ADC_ACQUISITION_TIME	ADC_ACQ_TIME_DEFAULT
#define ADC_CHANNEL_ID		23

#else
#error "Unsupported board."
#endif
*/

static const struct dac_channel_cfg dac_ch_cfg = {
	.channel_id = DT_PROP(DT_NODELABEL(DT_PATH(zephyr_user), dac-channel_id)),
	.resolution = DT_PROP(DT_NODELABEL(DT_PATH(zephyr_user), dac-resolution)),
	.buffered = true
};

static const struct adc_channel_cfg adc_ch_cfg = ADC_CHANNEL_CFG_DT(DT_CHILD(DT_NODELABEL(adc0), channel_e));/*{
	.gain             = ADC_GAIN,
	.reference        = ADC_REFERENCE,
	.acquisition_time = ADC_ACQUISITION_TIME,
	.channel_id       = ADC_CHANNEL_ID,*/


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
	int ret;
	const struct device *dac_dev = init_dac();
	const struct device *adc_dev = init_adc();

	if (!dac_dev || !adc_dev) {
		return TC_FAIL;
	}

	ret = dac_write_value(dac_dev, DT_PROP(DT_NODELABEL(DT_PATH(zephyr_user), dac_channel_id)), (1U << DT_PROP(DT_PATH(zephyr_user), dac_resolution) / 2)); // half value
	
	zassert_equal(ret, 0, "dac_write_value() failed with code %d", ret);

	k_sleep(K_MSEC(10));

	static int32_t m_sample_buffer[1];
	static const struct adc_sequence sequence = {
		.channels    = BIT(DT_PROP(DT_NODELABEL(adc0), zephyr_channel_id)),
		.buffer      = &m_sample_buffer,
		.buffer_size = sizeof(m_sample_buffer),
		.resolution  = DT_PROP(DT_NODELABEL(adc0), zephyr_resolution),
		};

	ret = adc_read(adc_dev, &sequence);
	
       	float val_mv = m_sample_buffer[0]; 
	
	val_mv  = (val_mv/4096 * 3.3); 

	zassert_equal(ret, 0, "adc_read() failed with code %d", ret);
	zassert_within(m_sample_buffer[0],
		(1U << DT_PROP(DT_NODELABEL(adc0), zephyr_resolution)) / 2, 32,
		"Value %d read from ADC does not match expected range.",
		m_sample_buffer[0]);
	
	printk("\n");
	printk("ADC VOLTAGE: %.3f\n", val_mv);
	printk("\n");
	return TC_PASS;
}

ZTEST(dac_adc_loop, test_dac_to_adc)
{
	zassert_true(test_dac_to_adc() == TC_PASS);
	test_dac_to_adc();
}

ZTEST_SUITE(dac_adc_loop, NULL, NULL, NULL, NULL, NULL);
