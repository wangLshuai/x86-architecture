SECTION header vstart=0
    program_length  dd program_end ;0x00
    entry           dd start

header_end:

SECTION data vfollows=header
        message: db '[User TASK1]: CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC,' ,0x0d,0x0a,0

data_end:

[bits 32]

SECTION code vfollows=data
start:
    ;在当前任务的虚拟空间中分配内存
    mov eax,4       ;调用号
    mov ecx,128
    int 0x88
    mov ebx,ecx

    mov esi,message
    mov edi,ecx
    mov ecx, data_end-message
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