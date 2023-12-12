#include <zephyr/drivers/adc.h>
#include <zephyr/ztest.h>

static const struct adc_dt_spec adc_channel = ADC_DT_SPEC_GET(DT_PATH(zephyr_user));

const struct adc_dt_spec *get_adc_channel(void)
{
	return &adc_channel;
}

static void *adc_setup(void)
{
	int ret;

	zassert_true(adc_is_ready_dt(&adc_channel), "ADC device is not ready");
	ret = adc_channel_setup_dt(&adc_channel);
	zassert_equal(ret, 0,
		"Setting up of the ADC channel failed with code %d", ret);

	return NULL;
}

ZTEST_SUITE(adc_accuracy_test, NULL, adc_setup, NULL, NULL, NULL);
