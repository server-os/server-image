# piadm(8) -- Manage ServerOS Platform Images


## SYNOPSIS
    /usr/sbin/piadm [-v | -vv] <command> [command-specific arguments]

    piadm activate|assign <PI-stamp> [ZFS-pool-name]
    piadm avail
    piadm bootable
    piadm bootable [-dr] <ZFS-pool-name>
    piadm bootable -e [ -i <source> ] <ZFS-pool-name>
    piadm install <source> [ZFS-pool-name]
    piadm list [ZFS-pool-name]
    piadm remove <PI-stamp> [ZFS-pool-name]
    piadm update [ZFS-pool-name]


## DESCRIPTION

    Historically, ServerOS booted off of a USB key or a read-only media like
    CD-ROM.  The copy and version of the ServerOS software on one of these
    media is called a Platform Image.  A Platform Image is described in
    detail in the next section.  The piadm(8) utility enables and manages
    the ability to instead boot directly off of a ZFS pool.

    piadm(8) manages multiple Platform Images on a bootable ZFS pool,
    allowing easier updates to Platform Images and maintaining multiple
    Platform Images on a single boot media.  The method and implementation of
    ServerOS booting does not change vs. a USB key or CD-ROM, but merely uses
    a bootable ZFS pool as the source of the Platform Image, which can be the
    traditional ServerOS `zones` pool if it is a bootable pool.

## PLATFORM IMAGES

    A ServerOS Platform Image (PI) is identified by creation timestamp,
    referred to here as a PI-stamp.  One can see it in uname(1):

        server(~)[0]% uname -a
        SunOS ServerOS-build 5.11 server-os_20200602T173751Z i86pc i386 i86pc
        server(~)[0]%

    The PI-stamp for this system's Platform Image is `20200602T173751Z`.

    The Platform Image is a directory containing:

        - A directory structure in a format used by loader(7).

        - The ServerOS `unix` kernel

        - The ServerOS boot archive containing kernel modules, libraries,
          commands, and more.

        - A manifest and hash.

        - A file containing the PI-stamp.

    The ServerOS loader(7) will find a path to a Platform Image on the
    bootable ZFS pool, and will load `unix` and then the boot archive.

    Platform images are supplied by either a gzipped tarball containing the
    above. Or inside an ISO image file which contains the above AND the boot
    image as well (see below).

## BOOT IMAGES

    In addition to platform images, the loader(7) also has a directory
    structure containing the loader itself and its support files.  These are
    stamped as well with PI stamps, but are distinct from the contents of a
    gzipped PI tarball.  Often, a PI can use an older Boot Image to boot
    itself without issue.  Occasionally, however, a PI will have Boot Image
    changes also that need to accompany it.


    The behavior of loader can be controlled by providing loader.conf.local
    and/or loader.rc.local files in the ${BOOTPOOL}/boot-${VERSION}
    directory. Loader config files can also be placed in ${BOOTPOOL}/custom,
    and will be used by all subsequently installed boot images.

    See loader.conf(5) and loader(7) for the format of these files.

## BOOTABLE POOLS

    A ServerOS bootable pool (POOL in the examples) contains:

        - A dataset named POOL/boot

        - A `bootfs` pool property set to POOL/boot.

        - At least an MBR on its physical disks for BIOS booting, or if the
          pool was created with `zpool create -B`, an EFI System Partition
          (ESP) with loader(7) installed in it.

        - At least one Platform Image in /POOL/boot/platform-<PI-stamp>.

        - At least one Boot Image in /POOL/boot/boot-<PI-stamp>.

        - A /POOL/boot/etc directory that indicates the PI-stamp for the Boot
          Image.

        - Symbolic links /POOL/boot/platform and /POOL/boot/boot that point
          to the Platform Image and Boot Image that will be used at the next
          boot.

    For example:

```
 [root@server-os ~]# piadm bootable
 standalone                     ==> BIOS and UEFI
 zones                          ==> non-bootable
 [root@server-os ~]# piadm list
 PI STAMP           BOOTABLE FILESYSTEM            BOOT IMAGE   NOW   NEXT
 20200714T195617Z   standalone/boot                next         yes   yes
 [root@server-os ~]# ls -l /standalone/boot
 total 7
 lrwxrwxrwx   1 root     root          23 Jul 15 04:22 boot -> ./boot-20200714T195617Z
 drwxr-xr-x   4 root     root          15 Jul 15 04:12 boot-20200714T195617Z
 drwxr-xr-x   3 root     root           3 Jul 15 04:22 etc
 lrwxrwxrwx   1 root     root          27 Jul 15 04:22 platform -> ./platform-20200714T195617Z
 drwxr-xr-x   4 root     root           5 Jul 15 04:12 platform-20200714T195617Z
 [root@server-os ~]#
```

## ServerOS COMPUTE NODES and iPXE

    The ServerOS Cloud Orchestration system is constructed to contain a Head
    Node (sometimes more than one) and several Compute Nodes.  The Compute
    Nodes use iPXE, an improved Preboot eXecution Environment (PXE) for
    network booting. Originally ServerOS Compute Nodes required a USB key which
    contained iPXE and booted directly into iPXE.

    piadm(8) can enable a ServerOS Compute Node's ZFS pool to boot iPXE,
    obviating the need for a USB key.  It detects if a machine is a ServerOS
    Compute Node, and enables maintenance of iPXE on the bootable pool.  Many
    piadm(8) subcommands are disabled on a ServerOS Compute Node.

    The layout of a ServerOS Compute Node bootable pool is limited to `boot`
    and `platform` symbolic links to a populated-with-iPXE `boot-ipxe`
    directory, and a mostly empty `platform-ipxe` directory.  There is an
    additional platform-STAMP for a backup on-disk PI, in case of emergency.
    This directory contains an additional in-directory `platform` link to
    enable its selection as a backup.

## ServerOS HEAD NODES

    The piadm(8) command can convert a USB-key-booting ServerOS Head Node into
    a ZFS-pool-booting one.  It can also transfer boot duties from an
    existing ZFS pool to a new one.

    The `piadm list` subcommand will also show Platform Images available to
    the Head Node, but it is highly recommended that Head Nodes continue to
    use sdcadm(1) for such information.

## COMMANDS

    The piadm(8) command will produce more verbose output if -v is stated
    prior to the command. If -vv is stated prior to the command, piadm(8)
    will produce both -v output and enable the shell's -x flag, which
    produces output of all of the commands run in the piadm(8) script.

    piadm(8) commands and options are:

      piadm activate <PI-stamp> [ZFS-pool-name]
      piadm assign <PI-stamp> [ZFS-pool-name]

        Activate a Platform Image for the next boot, on a specified ZFS pool
        if there are more than one bootable pools imported.  It is up to the
        administrator to know which pool the system will actually boot.  If a
        boot image with the specified PI-stamp is unavailable, a warning will
        be issued but the new PI will be activated anyway.

        `activate` and `assign` are synonyms, for those used to other
        distros' `beadm`, or ServerOS's `sdcadm platform`, respectively.

        This command is disallowed on ServerOS Compute Nodes.

      piadm avail

        Query the well-known ServerOS PI repository for available ISO images,
        listed by PI-Stamp. No PI-Stamps older than the currently running PI
        stamp will be listed.

        This command is disallowed on ServerOS Compute Nodes.

      piadm bootable [-d | -e [-i <source>] | -r] [ZFS-pool-name]

        Query or upgrade a ZFS pool's bootable status.  With no arguments,
        the status of all imported pools will be queried.  -d will disable a
        pool from being bootable, and -e will enable one.  If the -i flag
        specifies an installation source, see below in the `install`
        subcommand, it will be used.  Lack of -i is equivalent to `-i media`.
        As mentioned earlier, it is up to the administrator to know which
        pool the system will actually boot. Unlike install, this command will
        always attempt to install a corresponding boot image as well.

        The -r flag will refresh a bootable pool's MBR and/or ESP.  This is
        especially useful on mirror or raidz pools that have new devices
        attached.

        Some pools can only be bootable on systems configured to boot in
        legacy BIOS mode, while others can also be bootable from UEFI
        systems.  The `bootable` subcommand will indicate this.

        For ServerOS Compute Nodes, the -i option is disallowed.  Otherwise,
        this will enable a ServerOS Compute Node to boot iPXE from the disk,
        obviating the need for USB key with iPXE on it.  It will also allow
        boot to a backup PI that is either the currently-running PI, or the
        ServerOS default PI if the currently-running one is not available.  The
        iPXE is provided by the ServerOS Head Node, and if it needs updating,
        the `sdcadm experimental update-gz-tools` command will update it on
        the head node.  See below for post-bootable iPXE updating on the
        ServerOS Compute Node.

	For ServerOS Head Nodes, the -i option is also disabled.  When invoked
	with -e on a Head Node, the piadm(8) command will attempt to convert
	a pool to be bootable for a ServerOS Head Node.  If a Head Node is
	booting from a USB key, the boot data comes from the USB Key.  If a
	Head Node is booting from another pool, the boot data comes from the
	current booted pool.  After invoking `piadm bootable -e $POOL`, $POOL
	can boot the ServerOS Head Node, BUT any pre-reboot operations
	(regardless if the current Head Node boot comes from USB or an
	existing bootable pool), will not copy over to the newly-enabled
	bootable pool.  It is therefore recommended that a Head Node reboot
	to the newly-enabled pool as soon as possible.

      piadm install <source> [ZFS-pool-name]

        Installs a new Platform Image into the bootable pool.  If the source
        also contains the boot image (like an ISO does), the Boot Image will
        also be installed, if available.  If there are more than one bootable
        pools, a pool name will be required.  piadm(8) requires a Platform
        Image source.  That source can be:

          - A PI-stamp, which will consult the well-known ServerOS PI
            repository for an ISO image.  This requires network reachability
            and working name resolution.

          - The word "latest", which will consult the well-known ServerOS PI
            repository for the latest ISO image.  This requires network
            reachability and working name resolution.

          - The word "media", which will attempt to find a mountable optical
            media (CD or DVD) or USB-key with ServerOS on it.  The ServerOS
            installer uses this keyword.

          - An ISO image file path.

          - A PI gzipped tarball file path.  NOTE this source does not have
            a boot image in it.

          - A URL to either one of an ISO image or a gzipped PI tarball.

        This command is disallowed on ServerOS Compute Nodes.

      piadm list [ZFS-pool-name]

        Lists the available platform images (and boot images) on bootable
        pools.

      piadm remove <PI-stamp> [ZFS-pool-name]

        The opposite of `install`, and only accepts a PI-stamp.  If a boot
        image exists with the specified PI-stamp, it will also be removed
        unless it is the only boot image available.

        This command is disallowed on ServerOS Compute Nodes.

      piadm update [ZFS-pool-name]

        This command is exclusive to ServerOS Compute Nodes.  This command
        updates iPXE and loader (boot) for the specified pool on the ServerOS
        Compute Node.  If the ServerOS Compute Node has booted to a different
        PI than what is currently cached as the bootable backup PI, this
        command will update the bootable backup PI as well, or attempt to
        refresh the the ServerOS default PI.

## EXAMPLES

### Making a new bootable pool, and seeing the handiwork

```
 [root@server-os ~]# zpool create -f -B standalone c1t1d0
 [root@server-os ~]# piadm bootable
 standalone                     ==> non-bootable
 zones                          ==> non-bootable
 [root@server-os ~]# piadm -v bootable -e -i latest standalone
 Installing PI 20200701T231659Z
 Platform Image 20200701T231659Z will be loaded on next boot,
     with a new boot image,
     boot image  20200701T231659Z
 [root@server-os ~]# piadm bootable
 standalone                     ==> BIOS and UEFI
 zones                          ==> non-bootable
 [root@server-os ~]# piadm list
 PI STAMP           BOOTABLE FILESYSTEM            BOOT IMAGE   NOW   NEXT
 20200701T231659Z   standalone/boot                next         no    yes
 [root@server-os ~]#
```

### Installing a PI-only (use an old boot image) update and activating it

```
 [root@server-os ~]# piadm list
 PI STAMP           BOOTABLE FILESYSTEM            BOOT IMAGE   NOW   NEXT
 20200714T195617Z   standalone/boot                next         yes   yes
 [root@server-os ~]# piadm -v install https://example.com/PIs/platform-20200715T192200Z.tgz
 Installing https://example.com/PIs/platform-20200715T192200Z.tgz
         (downloaded to /tmp/tmp.Bba0Ac)
 Installing PI 20200715T192200Z
 [root@server-os ~]# piadm list
 PI STAMP           BOOTABLE FILESYSTEM            BOOT IMAGE   NOW   NEXT
 20200714T195617Z   standalone/boot                next         yes   yes
 20200715T192200Z   standalone/boot                none         no    no
 [root@server-os ~]# piadm -v activate 20200715T192200Z
 Platform Image 20200715T192200Z will be loaded on next boot,
     WARNING:  20200715T192200Z has no matching boot image, using
     boot image  20200714T195617Z
 [root@server-os ~]# piadm list
 PI STAMP           BOOTABLE FILESYSTEM            BOOT IMAGE   NOW   NEXT
 20200714T195617Z   standalone/boot                next         yes   no
 20200715T192200Z   standalone/boot                none         no    yes
 [root@server-os ~]#
```

## EXIT STATUS

The following exit values are returned:

     0
         Successful completion.

     1
         An error occurred, but no change was made

     2
         A fatal error occurred, and there may be partial change or
         other residual files or directories.

     3
         A corrupt environment on what is supposed to be a bootable pool.


## SEE ALSO

    sdcadm(1), loader.conf(5), loader(7), zpool(8)

## NOTES

    Many ZFS pool types are not allowed to be bootable.  The system's BIOS or
    UEFI must locate a bootable disk on a bootable pool in order to boot.
    Future work in illumos will enable more ZFS pool types to be bootable,
    but for now a ZFS pool should be a single-level-vdev pool, namely one of:

      - Single disk
      - Mirror
      - RaidZ (any parity)

    ServerOS still loads a ramdisk root with a read-only /usr filesystem, even
    when booted from a bootable pool.  This means a bootable pool that isn't
    the ServerOS `zones` pool receives relatively few writes unless it is used
    for some other purpose as well.

    A bootable pool created without the -B option, but using whole disks,
    will be BIOS bootable thanks to space for the MBR, but not bootable with
    UEFI.  A hand-partitioned GPT disk may be able to be bootable with both
    BIOS and UEFI, and can have some of its other GPT parititions used for
    other purposes.

    If a bootable pool's boot image or platform image becomes corrupt, even
    if it's `zones`, a machine can still be booted with a USB stick, CD-ROM,
    or other method of booting ServerOS.  A bootable pool can then be
    repaired using piadm(8) from the USB stick or CD-ROM.
