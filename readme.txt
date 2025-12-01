quick test on x86 machine:

CC=aarch64-linux-gnu-gcc make clean
CC=aarch64-linux-gnu-gcc make 

#this will push to device via adb and test
CC=aarch64-linux-gnu-gcc make test

