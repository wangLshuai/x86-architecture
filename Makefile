.PHONY:run
run: image
	./run.sh debug &
	# refer https://astralvx.com/debugging-16-bit-in-qemu-with-gdb-on-windows/
	gdb -ix gdb_init_real_mode.txt -ex "set tdesc filename target.xml"  -ex "target remote localhost:1234" -ex "b *0x7c00" -ex "c"

image: build
	dd if=/dev/zero of=image.raw bs=1M count=1
	dd if=boot.bin of=image.raw
build:boot.asm
	nasm -f bin boot.asm -o boot.bin

.PHONY:clean
	rm -rf *.bin