boot.bin: go.asm
	nasm -o $@ $^

.PHONY: run
run: boot.bin
	qemu-system-x86_64 $^ -display gtk,zoom-to-fit=on

