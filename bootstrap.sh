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
    sudo mkdir -p "$mnt"/dev

    #
    # /dev/null for dirmngr
    #
    # create /dev/null to avoid hanging dirmngr installation
    # that has "dirmngr </dev/null >&/dev/null" in it's postinstall hook
    # and without this line it creates regular file with tons of lines like:
    #
    #   dirmngr[21273]: No ldapserver file at: '/root/.gnupg/dirmngr_ldapservers.conf'
    #   dirmngr[21273.0]: permanently loaded certificates: 1
    #   dirmngr[21273.0]:     runtime cached certificates: 0
    #   dirmngr[21273.0]:            trusted certificates: 1 (0,0,0,1)
    #   dirmngr[21273.0]: failed to open cache dir file '/root/.gnupg/crls.d/DIR.txt': No such file or directory
    #   dirmngr[21273.0]: creating directory '/root/.gnupg'
    #   dirmngr[21273.0]: creating directory '/root/.gnupg/crls.d'
    #   dirmngr[21273.0]: new cache dir file '/root/.gnupg/crls.d/DIR.txt' created
    #   # Home: /root/.gnupg
    #   # Config: [none]
    #   OK Dirmngr 2.2.15 at your service
    #   ERR 167772435 Unknown IPC command <Dirmngr>
    #   ...
    #   ERR 167772435 Unknown IPC command <Dirmngr>
    sudo mknod "$mnt"/dev/null c 1 3

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

        -r "$mnt"
    )
    sudo pacman -Sy "${opts[@]}" "${pkgs[@]}" "$@"

    sudo cp $(path init) mnt/sbin/
}
function main()
{
    make_rootfs rootfs.img || return 1

    mkdir -p mnt
    sudo mount -o loop rootfs.img mnt
    configure_rootfs mnt "$@"
    configure_locales mnt
    sudo umount mnt
}
main "$@"
