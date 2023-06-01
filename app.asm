SECTION header vstart=0
    program_length  dd program_end ;0x00
    entry_point     dd start       ;0x04

header_end:

SECTION data vfollows=header
    message_1           db '[User TASK]: BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB,' ,0x0d,0x0a,0

    reserved times 4096*5 db 0 ;缓冲区

data_end:

[bits 32]

SECTION code vfollows=data
start:
    ;在当前任务的虚拟空间中分配内存
    mov eax,4       ;调用号
    mov ecx,128
    int 0x88
    mov ebx,ecx

    mov esi,message_1
    mov edi,ecx
    mov ecx, reserved-message_1
    cld
    repe movsb

.show:
    mov eax,0
    int 0x88
    ; hlt
    jmp .show


code_end:

SECTION program_trail 
program_end: