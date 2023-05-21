.PHONY:run
run: image
	./run.sh
.PHONY: debug
debug: image
	./run.sh debug &
	# refer https://astralvx.com/debugging-16-bit-in-qemu-with-gdb-on-windows/
	gdb -ex "target remote localhost:1234" -ex "b *0x7c00" -ex "c"

image: mbr.bin kernel.bin app.bin
	# dd if=/dev/zero of=image.raw bs=1M count=1
	dd if=mbr.bin of=image.raw conv=notrunc
	dd if=kernel.bin of=image.raw bs=512 seek=1 conv=notrunc
	dd if=app.bin of=image.raw bs=512 seek=50 conv=notrunc
mbr.bin:gdt_mbr.asm
	nasm -f bin gdt_mbr.asm -o mbr.bin

kernel.bin:kernel.asm
	nasm -f bin kernel.asm -o kernel.bin

app.bin:app.asm
	nasm -f bin app.asm -o app.bin

.PHONY:clean
clean:
	rm -rf *.bin *.o