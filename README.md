Few scripts to run kernel in qemu

### qemu-cli

- `bootstrap.sh` -- make rootfs image
- `qemu.sh` -- run the kernel

### Examples

#### Basic

```sh
./bootstrap.sh
./qemu.sh -k /path/to/bzImage
```

#### Wait for the action from the debugger

```
./qemu.sh -Q '-S' -k /path/to/bzImage
```
