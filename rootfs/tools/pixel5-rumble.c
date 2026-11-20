// SPDX-License-Identifier: MIT
/*
 * pixel5-rumble <ms> [magnitude 0-65535]
 * One FF_RUMBLE effect on the first input device named "drv2624-haptics"
 * (the mainline DRV2624 driver). Exits 3 if there is none.
 */
#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int find_dev(char *path, size_t len)
{
	DIR *d = opendir("/dev/input");
	struct dirent *e;
	int fd = -1;

	if (!d)
		return -1;
	while ((e = readdir(d))) {
		char name[64] = "";

		if (strncmp(e->d_name, "event", 5))
			continue;
		snprintf(path, len, "/dev/input/%s", e->d_name);
		fd = open(path, O_RDWR);
		if (fd < 0)
			continue;
		if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) >= 0 &&
		    !strcmp(name, "drv2624-haptics"))
			break;
		close(fd);
		fd = -1;
	}
	closedir(d);
	return fd;
}

int main(int argc, char **argv)
{
	char path[300];
	struct ff_effect fx;
	struct input_event ev;
	int ms, fd;

	if (argc < 2) {
		fprintf(stderr, "usage: pixel5-rumble <ms> [magnitude]\n");
		return 2;
	}
	ms = atoi(argv[1]);
	fd = find_dev(path, sizeof(path));
	if (fd < 0) {
		fprintf(stderr, "pixel5-rumble: no drv2624-haptics device\n");
		return 3;
	}
	memset(&fx, 0, sizeof(fx));
	fx.type = FF_RUMBLE;
	fx.id = -1;
	fx.u.rumble.strong_magnitude = argc > 2 ? atoi(argv[2]) : 0xffff;
	fx.replay.length = ms;
	if (ioctl(fd, EVIOCSFF, &fx) < 0) {
		perror("pixel5-rumble: EVIOCSFF");
		return 1;
	}
	memset(&ev, 0, sizeof(ev));
	ev.type = EV_FF;
	ev.code = fx.id;
	ev.value = 1;
	if (write(fd, &ev, sizeof(ev)) != sizeof(ev)) {
		perror("pixel5-rumble: play");
		return 1;
	}
	/* Closing the device stops the effect: stay until it has played. */
	usleep((ms + 50) * 1000);
	close(fd);
	return 0;
}
