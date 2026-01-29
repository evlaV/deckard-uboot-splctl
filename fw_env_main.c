// SPDX-License-Identifier: GPL-2.0+
/*
 * (C) Copyright 2000-2008
 * Wolfgang Denk, DENX Software Engineering, wd@denx.de.
 */

/*
 * Command line user interface to firmware (=U-Boot) environment.
 reworked for spl
 */

 //TODO: get the backup spl env working!!

#include <env.h>
#include <fcntl.h>
#include <getopt.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/file.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/stat.h>
//#include <version.h>
#include "fw_env_private.h"
#include "fw_env.h"
#include <sys/ioctl.h>
#include <linux/fs.h>
#include <sys/sysmacros.h>

//#define SPL_MODE_DISABLE_OVERRIDE_ALLOWED
//#define FORCE_RESCUE_ALLOWED

#define U_BOOT_VERSION "2026.1"

//prototypes
int fw_getenv_get_primary(struct env_opts *opts);
int fw_getenv_get_boot_count(struct env_opts *opts, char *target, int * boot_count_out_var);
int fw_getenv_get_state(struct env_opts *opts, char *target);
int fw_setenv_set_state(struct env_opts *opts, char *target, char* state);
int fw_setenv_set_primary(struct env_opts *opts, char *target);
int fw_setenv_force_rescue(struct env_opts *opts);
int fw_getenv_get_valid(struct env_opts *opts, char *target);
int fw_setenv_set_bootfw_slot(struct env_opts *opts, char *target);
int fw_getenv_get_bootfw_slot(struct env_opts *opts);

static struct env_opts env_opts;

static int g_blkdev_was_locked = 0;
static int g_blkdev_parent_was_locked = 0;

int blkroset(int fd, int setro_val)
{
	//using fd, get block maj:min
	//contents of /sys/dev/block/maj:min/../dev tells you the parent device blockdev maj:min
	//open the parent blockdev as well as the existing fd, then try to setro on both
	int ret = 0;
	unsigned dmaj,dmin;
	bool parent_exists = false;
	struct stat st;
	if (fstat(fd, &st) < 0) return -1;
	if (!S_ISBLK(st.st_mode)) return -1;

	char p[128];
	snprintf(p, sizeof(p), "/sys/dev/block/%u:%u/../dev", major(st.st_rdev), minor(st.st_rdev));
	FILE *f = fopen(p, "r");
	if (f) { parent_exists = (fscanf(f, "%u:%u", &dmaj, &dmin) == 2); fclose(f); }

	if(parent_exists)
	{
		//parent means we have an fd to /dev/sdc1 for example, so the parent would be /dev/sdc
		snprintf(p, sizeof(p), "/dev/block/%u:%u", dmaj, dmin);
		int fd_parent = open(p, O_RDONLY | O_CLOEXEC);
		if(fd_parent >= 0) 
		{
			//only set BLKROSET if the existing RO bit is enabled
			int getro_val = 0;
			ioctl(fd_parent, BLKROGET, &getro_val);
			if(getro_val == 1) g_blkdev_parent_was_locked = 1;
			if(g_blkdev_parent_was_locked) ioctl(fd_parent, BLKROSET, &setro_val); //ignore failure case
			close(fd_parent);
		}
	}

	//this could be either /dev/sdc1, or could even be /dev/sdc -- we can handle both situations
	//only set BLKROSET if the existing RO bit is enabled 
	int getro_val = 0;
	ioctl(fd, BLKROGET, &getro_val);
	if(getro_val == 1) g_blkdev_was_locked = 1;
	if(g_blkdev_was_locked) ret = ioctl(fd, BLKROSET, &setro_val);

	return ret;
}

int set_blockdev_ro(int set_read_only) 
{
    int fd;
    int ro = set_read_only;  // 1 sets the device to read-only, 0 sets to read-write
    int ret;

    fd = open(DEVICE1_NAME, O_RDONLY);
    if (fd < 0) {
		return 1;
    }

    blkroset(fd,set_read_only);

    close(fd);
    return 0;
}

#ifdef SPL_MODE_DISABLE_OVERRIDE_ALLOWED
int check_for_spl_mode_override_file(void)
{
	const char *path = "/tmp/spl_mode_disable.txt";
    struct stat sb;

    return stat(path, &sb) == 0;
}
#endif

int check_for_spl_partition(void)
{
	const char *path = DEVICE1_NAME;
    struct stat sb;

#ifdef SPL_MODE_DISABLE_OVERRIDE_ALLOWED
	if( check_for_spl_mode_override_file() ) 
	{
		//this is used to force us into the non-spl path for testing
		return 0;
	}
#endif		

    if (stat(path, &sb) == 0) {
        if (S_ISBLK(sb.st_mode))
		{
			return 1;
		}
        else
		{
			return 0;
		}

    } else 
	{
		return 0;
    }
}

int get_slot_from_kernel_command_line(void)
{
    int retval = 0;
	char *cmdline = NULL;
	size_t len = 0;

	FILE *fp = fopen("/proc/cmdline", "r");
	if (!fp) return EXIT_FAILURE;
    if (getline(&cmdline, &len, fp) == -1) {
		retval = EXIT_FAILURE;
		goto cleanup_and_exit;
    }

    const char *param = "rauc.slot=";
    char *start = strstr(cmdline, param);
    if (start) {
        start += strlen(param);
        char *end = strpbrk(start, " \n");
        if (end) *end = '\0';
        printf("%s\n", start);
    }
	else {
		retval = EXIT_FAILURE;
	}
	
cleanup_and_exit:
    fclose(fp);
    free(cmdline);
    return retval;

}

int parse_rauc_args(int argc, char *argv[])
{
	if ( argc == 2 && !strcmp( argv[ 1 ], "get-primary" ) )
	{
		fw_getenv_get_primary(&env_opts);
	}
	else if ( argc == 2 && !strcmp( argv[ 1 ], "get-current" ) )
	{
		get_slot_from_kernel_command_line();
	}
	else if ( argc == 3 && !strcmp( argv[ 1 ], "set-primary" ) )
	{
		//set primary implies setting A or B as primary, but also marking it as good
		set_blockdev_ro(0);
		fw_setenv_set_primary(&env_opts, argv[ 2 ]);
		set_blockdev_ro(1);
		set_blockdev_ro(0);
		fw_setenv_set_state(&env_opts, argv[ 2 ], "good"); 
		set_blockdev_ro(1);
	}
	else if ( argc == 3 && !strcmp( argv[ 1 ], "get-state" ) )
	{
		
		int ret = fw_getenv_get_state(&env_opts, argv[ 2 ]);
		if(ret) {
			int boot_count = -1;
			int retval = fw_getenv_get_boot_count(&env_opts, argv[ 2 ], &boot_count);
			//check if value is non-zero
			if(retval == 0)
			{
				printf(boot_count > 0 ? "good\n" :"bad\n" );
			}
		}
		return 0;
	}
	else if ( argc == 3 && !strcmp( argv[ 1 ], "get-valid" ) )
	{
		int ret = fw_getenv_get_valid(&env_opts, argv[ 2 ]);
		return 0;
	}
	else if ( argc == 3 && !strcmp( argv[ 1 ], "get-boot-count" ) )
	{
		fw_getenv_get_boot_count(&env_opts, argv[ 2 ], NULL);
	}
	else if ( argc == 4 && !strcmp( argv[ 1 ], "set-state" ) )
	{
		set_blockdev_ro(0);
		fw_setenv_set_state(&env_opts, argv[ 2 ], argv[ 3 ]);
		set_blockdev_ro(1);
	}
#ifdef FORCE_RESCUE_ALLOWED	
	else if ( argc == 2 && !strcmp( argv[ 1 ], "force-rescue" ) )
	{
		set_blockdev_ro(0);
		fw_setenv_force_rescue(&env_opts);
		set_blockdev_ro(1);
	}
#endif
	else if ( argc == 3 && !strcmp( argv[ 1 ], "set-bootfw-slot" ) )
	{
		//set primary implies setting A or B as primary, but also marking it as good
		set_blockdev_ro(0);
		fw_setenv_set_bootfw_slot(&env_opts, argv[ 2 ]);
		set_blockdev_ro(1);
	}
	else if ( argc == 2 && !strcmp( argv[ 1 ], "get-bootfw-slot" ) )
	{
		fw_getenv_get_bootfw_slot(&env_opts);
	}
	
	return 0;
}

int run_command(char * outbuff, int buffsize, char * command) 
{
    char buffer[buffsize];
	FILE *pipe = popen(command, "r");
    if (pipe == NULL) {
        return 1;
    }

	int offset = 0;
    while (fgets(buffer, sizeof(buffer), pipe) != NULL) 
	{
        int written = snprintf(outbuff + offset, buffsize - offset, "%s", buffer);
        if (written < 0) 
		{
            break;
        }
        if (offset + written >= buffsize) 
		{
            //truncated
            offset = buffsize - 1;
            break;
        }
        offset += written;
    }

    if (pclose(pipe) == -1) 
	{
        return 1;
    }

    return 0;
}

int parse_rauc_args_no_spl(int argc, char *argv[])
{
	char outbuffer[128];
	int ret = 0;

	//this will shell out to fw_printenv and fw_setenv
	if ( argc == 2 && !strcmp( argv[ 1 ], "get-primary" ) )
	{
		ret = run_command(outbuffer, sizeof(outbuffer), "fw_printenv -n BOOT_ORDER");
		printf("%c\n", outbuffer[0]);
	}
	else if ( argc == 2 && !strcmp( argv[ 1 ], "get-current" ) )
	{
		get_slot_from_kernel_command_line();
	}
	else if ( argc == 3 && !strcmp( argv[ 1 ], "set-primary" ) )
	{
		//set primary implies setting A or B as primary, but also marking it as good
		if(!strcmp(argv[ 2 ],"A"))
		{
			ret = run_command(outbuffer, sizeof(outbuffer), "fw_setenv BOOT_ORDER \"A B\"");
			ret = run_command(outbuffer, sizeof(outbuffer), "fw_setenv BOOT_A_LEFT 3");
		}
		if(!strcmp(argv[ 2 ],"B"))
		{
			ret = run_command(outbuffer, sizeof(outbuffer), "fw_setenv BOOT_ORDER \"B A\"");
			ret = run_command(outbuffer, sizeof(outbuffer), "fw_setenv BOOT_B_LEFT 3");
		}
	}
	else if ( argc == 3 && !strcmp( argv[ 1 ], "get-state" ) )
	{
		if(!strcmp(argv[ 2 ],"A"))
		{
			ret = run_command(outbuffer, sizeof(outbuffer), "fw_printenv -n BOOT_A_LEFT");
		}
		if(!strcmp(argv[ 2 ],"B"))
		{
			ret = run_command(outbuffer, sizeof(outbuffer), "fw_printenv -n BOOT_B_LEFT");
		}
		if(ret == 0)
		{	
			int boot_count = atoi(outbuffer);
			printf(boot_count > 0 ? "good\n" :"bad\n" );
		}
	}
	else if ( argc == 3 && !strcmp( argv[ 1 ], "get-boot-count" ) )
	{
		if(!strcmp(argv[ 2 ],"A"))
		{
			ret = run_command(outbuffer, sizeof(outbuffer), "fw_printenv -n BOOT_A_LEFT");
		}
		if(!strcmp(argv[ 2 ],"B"))
		{
			ret = run_command(outbuffer, sizeof(outbuffer), "fw_printenv -n BOOT_B_LEFT");
		}
		if(ret == 0)
		{	
			int boot_count = atoi(outbuffer);
			printf("%d\n",boot_count);
		}
	}
	else if ( argc == 4 && !strcmp( argv[ 1 ], "set-state" ) )
	{
		//set primary implies setting A or B as primary, but also marking it as good
		if(!strcmp(argv[ 2 ],"A") && !strcmp(argv[ 3 ],"good"))
		{
			ret = run_command(outbuffer, sizeof(outbuffer), "fw_setenv BOOT_A_LEFT 3");
		}
		else if(!strcmp(argv[ 2 ],"A") && !strcmp(argv[ 3 ],"bad"))
		{
			ret = run_command(outbuffer, sizeof(outbuffer), "fw_setenv BOOT_A_LEFT 0");
		}
		else if(!strcmp(argv[ 2 ],"B") && !strcmp(argv[ 3 ],"good"))
		{
			ret = run_command(outbuffer, sizeof(outbuffer), "fw_setenv BOOT_B_LEFT 3");
		}
		else if(!strcmp(argv[ 2 ],"B") && !strcmp(argv[ 3 ],"bad"))
		{
			ret = run_command(outbuffer, sizeof(outbuffer), "fw_setenv BOOT_B_LEFT 0");
		}
	}
	return 0;
}

int main(int argc, char *argv[])
{
	int ret = 0;
	int splenvexists = 0;

	splenvexists = check_for_spl_partition();

	if( splenvexists ) 
	{
		ret = parse_rauc_args(argc, argv);
		set_blockdev_ro(1); //ensure we leave things in a locked state
	}
	else
	{
		ret = parse_rauc_args_no_spl(argc, argv);
	}

	exit( ret ? EXIT_FAILURE : EXIT_SUCCESS);

}

