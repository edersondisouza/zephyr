#ifndef __EXT2_H__
#define __EXT2_H__
#include <zephyr/kernel.h>

#include <app_api.h>

int internal_pub(enum Channels channel, void *data,
		 size_t data_len);
#endif
