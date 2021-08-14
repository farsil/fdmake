; vim:ft=tasm
ideal
model tiny
jumps
p8086

; Newline \r\n
nl equ 10,13

; Horizontal tab \t
tab equ 9

; Force overwrite and write filesystem flags
overwrite = 01h
nofs = 02h

; Floppy disk specification
struc fdspec
    chs   dw ? ; Cylinders * Heads * Sectors
    h     db ? ; Heads
    s     db ? ; Sectors
    mdesc db ? ; Media descriptor
    spc   db ? ; Sectors per cluster
    fatsz db ? ; FAT volume size in sectors
    rtent dw ? ; Root directory entries
ends

; Floppy disk specification offsets
fd360 = offset fdtable
fd720 = offset fdtable + size fdspec
fd1200 = offset fdtable + 2 * (size fdspec)
fd1440 = offset fdtable + 3 * (size fdspec)
fd2880 = offset fdtable + 4 * (size fdspec)

; Tag offsets (read from usagetxt to save space)
t360 = offset m_usage + 141
t720 = t360 + 6
t1200 = t720 + 6
t1440 = t1200 + 6
t2880 = t1440 + 17

dataseg
    m_usage db \
        "Creates a floppy disk image.",nl,nl,\
        "FDMAKE filename [/T type] [/L label] [/U] [/F]",nl,nl,\
        "  filename  ",\
        "Image file to create.",nl,\
        "  /T",tab,"    ",\
        "Type of image: 360k, 720k, 1.2m, 1.44m (default), 2.88m.",nl,\
        "  /L",tab,"    ",\
        "Volume label (max 11 characters), ignored if /U is set.",nl,\
        "  /U",tab,"    ",\
        "Writes an unformatted image.",nl,\
        "  /F",tab,"    ",\
        "Overwrites the existing image file if it exists.",nl,nl,'$'

    e_exists db \
        "The file already exists. ",\
        "You can specify /F to overwrite it.",nl,'$'
    e_create db "Unable to create image file.",nl,'$'
    e_size db "Not enough space available for the image file.",nl,'$'
    e_bsect db "Unable to write image file boot sector.",nl,'$'
    e_fat db "Unable to write image file FAT.",nl,'$'
    e_vlabel db \
        "Unable to write image file filesystem entry ",\
        "for volume label.",nl,'$'

    fdtable fdspec \
        {chs=720, h=2, s=9,  mdesc=0FDh, spc=1, fatsz=3, rtent=112 }, \
        {chs=1440, h=2, s=9,  mdesc=0F9h, spc=1, fatsz=5, rtent=112 }, \
        {chs=2400, h=2, s=15, mdesc=0F9h, spc=1, fatsz=8, rtent=224 }, \
        {chs=2880, h=2, s=18, mdesc=0F0h, spc=1, fatsz=9, rtent=224 }, \
        {chs=5760, h=2, s=36, mdesc=0F0h, spc=2, fatsz=9, rtent=512 }

    fdptr  dw fdspec ptr fd1440
    fname  db 13 dup(0)
    vlabel db 11 dup(' '), 08h      ; 08h terminates the special FS entry
    fat    db ?, 0FFh, 0FFh, 00h    ; first byte is mdesc
    flags  db 0

    bsect  db 0EBh, 03Ch, 090h, \   ; jump to boot code
              "MSDOS5.0", \         ; OEM name
              00h, 02h, \           ; bytes per sector
              ?, \                  ; sectors per cluster (0Dh)
              01h, 00h, \           ; size of reserved area
              02h, \                ; number of FATs
              ?, ?, \               ; root entries  (11h-12h)
              ?, ?, \               ; total number of sectors (small, 13h-14h)
              ?, \                  ; media descriptor (15h)
              ?, 00h, \             ; fat size (16h-17h)
              ?, 00h, \             ; sectors (18h-19h)
              ?, 00h, \             ; heads (1Ah-1Bh)
              00h, 00h, 00h, 00h, \ ; sectors before partition
              00h, 00h, 00h, 00h, \ ; total number of sectors (large, unused)
              00h, \                ; removable disk
              00h, \                ; unused
              29h, \                ; extended boot signature
              ?, ?, ?, ?, \         ; volume serial number (27h-2Ah)
              "NO NAME    ", \      ; volume label (2Bh-35h)
              "FAT12   ", \         ; filesystem type
              448 dup(00h), \       ; unused
              055h, 0AAh            ; signature value

codeseg
    startupcode
    mov bx, 0080h
    add bl, [0080h]
    mov [byte ptr bx+1], ' ' ; add a space to the end of the arguments list
    mov si, 0081h
    call parse
    call prepare
    call write
    exitcode 0

; Parses the command line arguments and writes the appropriate memory areas
; with the provided options. Displays the usage message and quits with exit
; code 1 if any argument is invalid or if the filename is not specified.
; If filename or label are longer than allowed they are truncated.
;
; input
;   si: arugments string start
;   bx: arguments string length
;
; output
;   [fdptr]: pointer to the fdspec associated to the floppy disk type
;   [fname]: image filename, asciiz
;   [vlabel]: image label, space-padded to 11 characters
;   [flags]: overwrite and nofs flags, if set
;
; uses
;  ax, cx, si, di
proc parse
    cmp bl, 80h
    je @@usage      ; bl = 80h means no command line arguments

@@parse:
    cmp si, bx
    jge @@return
    lodsb

    cmp al, ' '
    je @@parse
    cmp al, '/'
    je @@option

@@filename:
    lea di, [fname]
    cmp [byte ptr di], 0
    jne @@usage     ; error if the filename was already set

    stosb           ; stores the first byte
    mov cx, 11      ; should be 12, but we already stored the first byte
    call movsl
    jmp @@parse

@@option:
    lodsw
    cmp ah, ' '
    jne @@usage     ; the lookahead byte is not a space, flag is invalid

    or al, 20h      ; case-insensitive switch on al
    cmp al, 'f'
    je @@overwrite
    cmp al, 'l'
    je @@vlabel
    cmp al, 't'
    je @@type
    cmp al, 'u'
    jne @@usage     ; if al is not 'u' we have an unrecognized flag

@@nofs:
    or [flags], nofs
    jmp @@parse

@@overwrite:
    or [flags], overwrite
    jmp @@parse

@@vlabel:
    lea di, [vlabel]
    mov cx, 11
    call movsl
    jmp @@parse

@@type:
    mov ax, si      ; backs up the address of the argument being parsed
    mov di, offset t360
    mov cx, 4
    mov [fdptr], offset fd360
    repe cmpsb
    je @@parse

    mov si, ax
    mov di, offset t1440
    mov cx, 5
    mov [fdptr], offset fd1440
    repe cmpsb
    je @@parse

    mov si, ax
    mov di, offset t720
    mov cx, 4
    mov [fdptr], offset fd720
    repe cmpsb
    je @@parse

    mov si, ax
    mov di, offset t1200
    mov cx, 4
    mov [fdptr], offset fd1200
    repe cmpsb
    je @@parse

    mov si, ax
    mov di, offset t2880
    mov cx, 5
    mov [fdptr], offset fd2880
    repe cmpsb
    je @@parse

@@usage:
    cmp ah, ' '
    lea dx, [m_usage]
    mov ah, 09h
    int 21h
    exitcode 1

@@return:
    ret
endp

; MOVe String Loop
;
; Move string until a space character is encountered. Copies at most cx bytes,
; and discards the rest.
;
; input
;   si: source address
;   di: destination address
;   cx: max length
;
; output
;   si: address of the space character
;
; uses
;   ax, cx, si, di
proc movsl
    add cx, di

@@move:
    cmp di, cx
    je @@discard    ; max length reached, truncate
    lodsb
    cmp al, ' '
    je @@return
    stosb
    jmp @@move

@@discard:
    mov al, ' '
    mov di, si
    repne scasb
    mov si, di

@@return:
    ret
endp

; Prepares the write buffers with the floppy disk metadata supplied by the user
; via command line options.
;
; input
;   [fdptr]: pointer to the floppy disk specification
;   [vlabel]: space-padded disk label
;
; output
;   [bsect]: updated with the specified disk metadata
;   [fat]: updated with the specified media descriptor
;
; uses
;   ax, bx, cx, dx, si, di
proc prepare
    mov bx, [fdptr]
    lea si, [bx + fdspec.spc]
    lea di, [bsect + 0Dh]
    movsb
    lea si, [bx + fdspec.rtent]
    lea di, [bsect + 11h]
    movsw
    lea si, [bx + fdspec.chs]
    lea di, [bsect + 13h]
    movsw
    mov al, [bx + fdspec.mdesc]
    mov [bsect + 15h], al
    mov [fat], al       ; the media descriptor is needed in the fat buffer too
    lea si, [bx + fdspec.fatsz]
    lea di, [bsect + 16h]
    movsb
    lea si, [bx + fdspec.s]
    lea di, [bsect + 18h]
    movsb
    lea si, [bx + fdspec.h]
    lea di, [bsect + 1Ah]
    movsb

    mov ah, 2Ch
    int 21h             ; get time
    xor ah, ah
    mov al, cl
    shl ax, 5
    shl ch, 3
    or ah, ch           ; time ts bit layout
    shr dh, 1           ; hour (1-5), month (7-11), second (12-16)
    or al, dh           ; takes the first 4 msb of second count
    lea di, [bsect + 27h]
    stosw

    mov ah, 2Ah
    int 21h             ; get date
    xor ah, ah
    mov al, dh
    shl ax, 5
    shl cx, 9           ; date ts bit layout
    or ax, cx           ; year (1-7), month (8-11), day (12-16)
    or al, dl           ; takes the last 7 lsb of year count
    lea di, [bsect + 29h]
    stosw

    mov al, 20h
    cmp al, [vlabel]    ; if first character is a space, no label was set
    je @@nolabel

    mov cx, 11
    lea si, [vlabel]
    lea di, [bsect + 2Bh]
    rep movsb

@@nolabel:
    ret
endp

; Writes the image file from the write buffers. The write buffers must be
; previously populated with the prepare procedure, otherwise garbage data
; will be written.
;
; This procedure terminates with an exit code of 2 and displays an error if
; a write error occurs, or if the user attempts to overwrite an existing
; image file without the overwrite flag.
;
; input
;   [fname]: the image disk filename
;   [flags]: overwrite and nofs flags
;   [fdptr]: pointer to the floppy disk specification
;   [bsect]: prepared boot sector
;   [fat]: prepared FAT
;   [vlabel]: space-padded disk label
;
; uses
;   ax, bx, cx, dx, si, di
proc write
    lea dx, [fname]
    mov ah, overwrite
    and ah, [flags]
    jnz @@create        ; skip file existence check if overwrite is set

@@check:
    mov ax, 3D00h
    int 21h             ; tries to read the specified filename, if exists
    mov bx, ax          ; it will produce an error
    lea dx, [e_exists]
    jnc @@error

@@create:
    mov ah, 3Ch
    xor cx, cx
    int 21h             ; create the specified filename
    jc @@nocreate
    mov bx, ax          ; file handle stays in bx

    mov si, [fdptr]
    mov ax, [si + fdspec.chs]
    mov dx, ax          ; this series of shifts multiply the content of
    shl dx, 9           ; ax by 512 and stores the result in cx:dx (high/low)
    mov cx, ax
    shr cx, 7

    mov ax, 4200h
    int 21h             ; seek to the projected file size (chs * 512)
    lea dx, [e_size]    ; preload error message
    jc @@error

    mov ah, 40h
    xor cx, cx
    int 21h             ; extends the file to the current location
    jc @@error          ; dx for the error message is left untouched by 40h

    mov ah, nofs
    and ah, [flags]
    jnz @@close         ; do not write filesystem info if nofs is set

    mov ax, 4200h
    xor dx, dx
    int 21h             ; seek back to the start of the file
    lea dx, [e_bsect]
    jc @@error

    mov ah, 40h
    mov cx, 512
    lea dx, [bsect]
    int 21h             ; write the prepared boot sector
    lea dx, [e_bsect]
    jc @@error

    mov ah, 40h
    mov cx, 4
    lea dx, [fat]
    int 21h             ; writes the first FAT (after the boot sector)
    lea dx, [e_fat]
    jc @@error

    mov ax, 4201h
    xor cx, cx
    xor dh, dh
    mov dl, [si + fdspec.fatsz]
    shl dx, 9
    sub dx, 4
    mov di, dx          ; back up dx in the only free register
    int 21h             ; seeks to the second FAT (cur + 512 * fatsz - 4)
    lea dx, [e_fat]
    jc @@error

    mov ah, 40h
    mov cx, 4
    lea dx, [fat]
    int 21h             ; writes the second FAT (after the first FAT)
    lea dx, [e_fat]
    jc @@error

    mov ax, 4201h
    xor cx, cx
    mov dx, di          ; restore the previosuly computed offset
    int 21h             ; seeks to the fs entries (cur + 512 * fatsz - 4)
    lea dx, [e_vlabel]
    jc @@error

    mov al, ' '
    cmp al, [vlabel]    ; if first character is a space, don't write the label
    je @@close          ; special fs entry

    mov ah, 40h
    mov cx, 12
    lea dx, [vlabel]
    int 21h             ; writes the special label fs entry
    lea dx, [e_vlabel]
    jc @@error

@@close:
    mov ah, 3Eh
    int 21h
    ret

@@nocreate:
    lea dx, [e_create]
    mov ah, 09h
    int 21h
    exitcode 2

@@error:
    mov ah, 3Eh
    int 21h
    mov ah, 09h         ; dx should be set beforehand!
    int 21h
    exitcode 2
endp

end
