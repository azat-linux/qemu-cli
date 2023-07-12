#!/usr/bin/env bash

function find_kernel()
{
    local paths=(
        /src/linux/arch/x86/boot/bzImage
    )

    for path in "${paths[@]}"; do
        [ -f $path ] && {
            echo $path
            return
        }
    done
}

function qemu()
{
    local kernel_opts=(
        console=ttyS0
        root=/dev/vda
        raid=noautodetect
        # panic_on_warn=1
        panic=-1
        intel_iommu=on
        # breaks debugger
        nokaslr
        mitigations=off
        audit=0

        "${kernel_args[@]}"
    )

    local cpus=$(getconf _NPROCESSORS_ONLN)
    local qemu_opts=(
        -enable-kvm
        -machine q35,accel=kvm
        -device intel-iommu
        -name linux-dev

        -no-reboot
        # shorthand for -gdb tcp::1234
        -s

        -nographic
        -serial mon:stdio

        # snapshot by default, <Ctrl-T s> to manually flush
        -drive if=virtio,file="$rootfs_image",$drive_opts

        -append "${kernel_opts[*]}"

        # <Ctrl-T> as an escape character
        # (since default <Ctrl-A> is tmux control-key)
        -echr 0x14

        -smp $(( cpus/2 ))
        -m 1G
    )
    qemu-system-x86_64 "${qemu_opts[@]}" "$@"
}

function make_spare_drive()
{
    local i="$1" size="$2"
    shift 2

    local path="$i.img"
    [ -f "$path" ] || fallocate -l "$size" "$path"
    echo "$path"
}
function make_spare_drive_in_mem()
{
    local i="$1" size="$2"
    shift 2

    local path="/dev/shm/$i.img"
    fallocate -l "$size" "$path"
    echo "$path"
}
function make_drive()
{
    local path="$1"
    shift

    local base="$(basname "$path")"
    fallocate -l1G "$base.img"
    mke2fs -F -t ext4 "$base.img"
    mkdir -p "$mnt.mnt"
    sudo mount -o loop "$base.img" "$mnt.mnt"
    rsync -a "$path" "$mnt.mnt"
    sudo umount "$mnt.mnt"

    echo "$base.img"
}
function parse_drives()
{
    local i
    for i in "$@"; do
        # it is likely some qemu option
        if [ "${i:0:1}" == "-" ]; then
            qemu_args+=( "$i" )
            continue
        fi

        if [ -f "$i" ]; then
            qemu_args+=( "-drive" "if=ide,file=$i" )
            continue
        fi

        if [ -d "$i" ]; then
            local drive="$(make_drive "$i")"
            qemu_args+=( "-drive" "if=ide,file=$drive" )
            continue
        fi

        echo "Unknown option: $i" >&2
        return 2
    done
}

declare -A opts
function usage()
{
    cat <<EOL
  $0 [ OPTS ] -- [ DRIVE/PATH/... ] [ QEMU OPTS ]

Options:
  -p preserve spare drives
  -S <size of spare drive>
  -M <size of spare drive in memory>
  -K <kernel arg, cmdline>
  -Q <qemu args> (i.e. -S)
  -k <kernel image>
  -i <rootfs image>
EOL
}
function parse_opts()
{
    local OPTARG OPTIND c

    qemu_args=()
    kernel_image=$(find_kernel)
    rootfs_image=rootfs.img
    drive_opts=()
    kernel_args=()
    qemu_args=()
    spare_preserve=0
    spare_drives=()
    spare_drives_in_mem=()

    cleanup_images=()

    while getopts "hsS:M:K:Q:k:i:p" c; do
        case "$c" in
            s)
                echo "snapshot mode is used, <Ctrl-T s> to manually flush"
                drive_opts="snapshot=on"
                ;;
            S) spare_drives+=($OPTARG);;
            M) spare_drives_in_mem+=($OPTARG);;
            p) spare_preserve=1;;
            K) kernel_args+=($OPTARG);;
            Q) qemu_args+=($OPTARG);;
            k) kernel_image=$OPTARG;;
            i) rootfs_image=$OPTARG;;
            h) usage && exit 0;;
            *) usage >&2 && exit 1;;
        esac
    done

    for ((i = 0; i < ${#spare_drives[@]}; ++i)); do
        local size="${spare_drives[$i]}"
        local img="$(make_spare_drive $i $size)"
        [ $spare_preserve -eq 1 ] || cleanup_images+=( "$img" )
        qemu_args+=(
            "-drive"
            "if=ide,file=$img,$drive_opts"
        )
    done

    for ((i = 0; i < ${#spare_drives_in_mem[@]}; ++i)); do
        local size="${spare_drives_in_mem[$i]}"
        local img="$(make_spare_drive_in_mem $i $size)"
        [ $spare_preserve -eq 1 ] || cleanup_images+=( "$img" )
        qemu_args+=(
            "-drive"
            "if=ide,file=$img,$drive_opts"
        )
    done

    qemu_args+=( -kernel "$kernel_image" )

    shift $(( OPTIND-1 ))
    parse_drives "$@" || return
}
function main()
{
    parse_opts "$@" || return
    qemu "${qemu_args[@]}"
    [[ -z "${cleanup_images[@]}" ]] || rm -fr "${cleanup_images[@]?}"
}
main "$@"
