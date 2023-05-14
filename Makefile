.PHONY:run
run: image
	./run.sh debug &
	# refer https://astralvx.com/debugging-16-bit-in-qemu-with-gdb-on-windows/
	gdb -ix gdb_init_real_mode.txt -ex "set tdesc filename target.xml"  -ex "target remote localhost:1234" -ex "b *0x7c00" -ex "c"

image: mbr.bin kernel.bin
	# dd if=/dev/zero of=image.raw bs=1M count=1
	dd if=mbr.bin of=image.raw conv=notrunc
	dd if=kernel.bin of=image.raw bs=512 seek=100 conv=notrunc
mbr.bin:mbr.asm
	nasm -f bin mbr.asm -o mbr.bin

kernel.bin:app2.asm
	nasm -f bin app2.asm -o kernel.bin

.PHONY:clean
clean:
	rm -rf *.bin *.o