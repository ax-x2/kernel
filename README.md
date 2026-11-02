## kernel setup
important: before running the setup scripts, make sure that the kernel version you intend to use is compatible with your build. not every kernel version is necessarily supported.

## debian (tested on debian 12/13)
```
chmod +x debian_setup.sh
./debian_setup.sh KERNEL_VERSION
```

## ubuntu (tested on ubuntu 24.04.5)
```
chmod +x ubuntu_setup.sh
./ubuntu_setup.sh KERNEL_VERSION
```

check that secure boot is not blocking the custom kernel

```
mokutil --sb-state
```

if secure boot is enabled, it may prevent unsigned custom kernel modules or kernels from loading.