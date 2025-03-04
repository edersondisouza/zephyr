#include <ext2.h>

#include <app_api.h>

int internal_pub(enum Channels channel, void *data,
		 size_t data_len)
{
	printk("[ext2]Publishing tick\n");
	return publish(channel, data, data_len);
}
