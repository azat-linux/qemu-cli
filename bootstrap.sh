#!/usr/bin/env bash

function path() { echo "$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")/$*"; }

function make_rootfs()
{
    local img="$1"
    shift

    fallocate -l5G "$img"
    mke2fs -F -t ext4 "$img" "$@"
}
function configure_locales()
{
    local mnt="$1"
    shift

    echo "en_US.UTF-8 UTF-8" | sudo tee -a "$mnt"/etc/locale.gen
    sudo chroot mnt locale-gen
}
function configure_rootfs()
{
    local mnt="$1"
    shift

    sudo mkdir -p "$mnt"/var/lib/pacman

    local pkgs=(
        # base
        base bash glibc coreutils e2fsprogs which procps-ng util-linux
        findutils grep gawk vi less sed
        bzip2 gzip tar
        pciutils
        # net
        bind-tools dhcp dhcpcd inetutils iproute2 iputils
        # debug
        strace tcpdump perf gdb
        # stuff
        tmux
    )
    local opts=(
        # we have our own kernel
        --ignore linux*
        # but some packages requires api headers and without this there will
        # endless loop for resolving dependency
        --assume-installed linux-api-headers=$(uname -r)

        # ignore gnupg, since this interacts with main dirmngr and send a lot
        # of invalid commands to it:
        #     read(3, "ERR 167772435 Unknown IPC command <Dirmngr>\nERR 167772435 Unknown IPC command <Dirmngr>\nERR 167772435 Unknown IPC command <Dirmngr>\nERR 167772435 Unknown IPC command <Dirmngr>\nERR 167772435 Unknown IPC command <Dirmngr>\nERR 167772435 Unknown IPC command <Dirmngr>\nERR 167772435 Unknown IPC command <Dirmngr>\nERR 167772435 Unknown IPC command <Dirmngr>\nERR 167772435 Unknown IPC command <Dirmngr>\n", 1002) = 396
        #     write(4, "ERR 167772435 Unknown IPC command <Dirmngr>", 43) = 43
        #     write(4, "\n", 1)                       = 1
        #     write(4, "ERR 167772435 Unknown IPC command <Dirmngr>", 43) = 43
        #     write(4, "\n", 1)                       = 1
        --ignore gnupg
        --ignore gpgme
        --assume-installed gpgme=1.11.1-2

        -r "$mnt"
    )
    sudo pacman -Sy "${opts[@]}" "${pkgs[@]}"

    sudo cp $(path init) mnt/sbin/
}
function main()
{
    make_rootfs rootfs.img || return 1

    mkdir -p mnt
    sudo mount -o loop rootfs.img mnt
    configure_rootfs mnt
    configure_locales mnt
    sudo umount mnt
}
main "$@"
