action_menu:
    push bc
    push hl
    push de
        ld c, 40
        kld(hl, menuOptions)
        corelib(showMenu)
        cp 0xFF
        kjp(z, freeAndLoopBack)
        add a, a ; A *= 2
        kld(hl, menu_functions)
        add a, l \ ld l, a \ jr nc, $+3 \ inc h
        ld e, (hl) \ inc hl \ ld d, (hl)
        ex de, hl
        push hl
            pcall(getCurrentThreadId)
            pcall(getEntryPoint)
        pop bc
        add hl, bc
        kld((.menu_smc + 1), hl)
    pop de
    pop hl
    pop bc
.menu_smc:
    jp 0
menu_functions:
    .dw action_new
    .dw action_delete
    .dw freeAndLoopBack ; Rename
    .dw action_exit

action_new:
    push bc
    push hl
    push de
        ; Check if symlink option should be shown
        kld(a, (config_editSymLinks))
        or a
        jr z, _
        ld a, 2
        jr ++_
_:      ld a, 1
_:      kld((newOptions), a)
        ; Show menu
        ld c, 42
        kld(hl, newOptions)
        corelib(showMenu)
        cp 0xFF
        kjp(z, freeAndLoopBack)
        add a, a ; A *= 2
        kld(hl, new_menu_options)
        add a, l \ ld l, a \ jr nc, $+3 \ inc h
        ld e, (hl) \ inc hl \ ld d, (hl)
        ex de, hl
        push hl
            pcall(getCurrentThreadId)
            pcall(getEntryPoint)
        pop bc
        add hl, bc
        kld((.menu_smc + 1), hl)
    pop de
    pop hl
    pop bc
.menu_smc:
    jp 0
new_menu_options:
    .dw action_new_directory ; Directory
    .dw action_new_link ; Link

action_exit:
    pcall(exitThread)

action_new_directory:
    ld bc, 33 ; TODO: better max name length
    pcall(malloc)
    ld (ix), 0
    kld(hl, createDirPrompt)
    dec bc
    corelib(promptString)
    or a
    kjp(z, freeAndLoopBack)
    ; Create new directory
    kcall(addToCurrentPath)
    kld(de, (currentPath))
    pcall(createDirectory)
    jr z, _
    corelib(showError)
_:  kcall(restoreCurrentPath)
    kjp(freeAndLoopBack)

action_new_link:
    ; Get target path and link name
    ld bc, 0x42 ; TODO: better max name length
    pcall(malloc)
    ld (ix), 0
    kld(hl, createLinkTargetPrompt)
    ld bc, 0x20
    corelib(promptString)
    or a
    kjp(z, freeAndLoopBack)
    add ix, bc
    inc ix
    ld (ix), 0
    kld(hl, createLinkNamePrompt)
    corelib(promptString)
    or a
    kjp(z, freeAndLoopBack)
    ; Add link name to current dir
    kcall(addToCurrentPath)
    ; Create link
    kld(de, (currentPath))
    pcall(memSeekToStart)
    push ix \ pop hl
    pcall(createSymLink)
    ; Show error if it failed
    jr z, _
    corelib(showError)
    ; Remove link name from current dir
_:  kcall(restoreCurrentPath)
    kjp(freeAndLoopBack)
    
action_delete:
    ld a, d
    cp b
    jr c, .deleteDirectory
    push de
    push bc
        kld(hl, deletionMessage)
        kld(de, deletionOptions)
        xor a
        ld b, 0
        corelib(showMessage)
    pop bc
    pop de
    or a ; cp 0
    kjp(z, freeAndLoopBack)
    ; DELETE IT
    ; Load it onto currentPath for a moment
    ld a, d
    sub b
    add a, a
    kld(hl, (fileList))
    add l
    ld l, a
    jr nc, $+3
    inc h
    ld e, (hl)
    inc hl
    ld d, (hl)
    inc de \ inc de
    kld(hl, (currentPath))
    xor a
    ld bc, 0
    cpir
    dec hl
    ex de, hl
    pcall(strlen)
    inc bc
    ldir
    kld(de, (currentPath))
    pcall(deleteFile)

    ex de, hl
    pcall(strlen)
    add hl, bc
    ld a, '/'
    cpdr
    inc hl ; preserve trailing slash
    inc hl
    xor a
    ld (hl), a
    kjp(freeAndLoopBack)
.deleteDirectory:
    ; TODO: delete directories
    ret

action_open:
    sub b
    add a, a
    kld(hl, (fileList))
    add l
    ld l, a
    jr nc, $+3 \ inc h
    ld e, (hl)
    inc hl
    ld d, (hl)
    inc de \ inc de
.with_de:
    ; Copy DE into the current path, but not for long
    kld(hl, (currentPath))
    xor a
    ld bc, 0
    cpir
    dec hl
    di
    push hl
        ex de, hl
        pcall(strlen)
        inc bc
        ldir
        kld(de, (currentPath))
        corelib(open)
    pop hl
    push af
        xor a
        ld (hl), a
    pop af
    jr nz, .fail
    ; Set up the trampoline
    ; This is what takes users back to fileman when the program exits
    push hl
    push de
    push ix
        ld bc, trampoline_end - trampoline
        pcall(malloc)
        pcall(reassignMemory)
        kld(hl, trampoline)
        push ix \ pop de
        ldir
        push ix \ pop hl
        pcall(setReturnPoint)
        pcall(getCurrentThreadId)
        ld (ix + 1), a
    pop ix
    pop de
    pop hl
    ei
    pcall(suspendCurrentThread)
    kjp(freeAndLoopBack)
.fail:
    ei
    ; It failed to open, complain to the user
    kld(hl, openFailMessage)
    kld(de, openFailOptions)
    xor a
    ld b, 0
    corelib(showMessage)
    kjp(freeAndLoopBack)

trampoline:
    ld a, 0 ; Thread ID will be loaded here
    pcall(checkThread)
    corelib(nz, launchCastle)
    pcall(nz, killCurrentThread)
    ld (hwLockLCD), a
    ld (hwLockKeypad), a
    pcall(resumeThread)
    pcall(killCurrentThread)
trampoline_end:

addToCurrentPath:
    ; Add file name at IX to current dir
    push ix \ pop de
    kld(hl, (currentPath))
    xor a
    ld bc, 0
    cpir
    dec hl
    ex de, hl
    pcall(strlen)
    inc bc
    ldir
    ret

restoreCurrentPath:
    ; Remove file name from current path
    ex de, hl
    pcall(strlen)
    add hl, bc
    inc bc
    ld a, '/'
    cpdr
    inc hl
    inc hl
    xor a
    ld (hl), a
    ret
