Scripts used to unpack 003_Family_11.1.5.dmg on Linux without hdiutil, xar or cpio.

    python3 -I udif.py 003_Family_11.1.5.dmg 003.img      # DMG -> raw disk image
    grep -obUaP 'xar!' 003.img                             # find the installer pkg offset
    python3 -I xar.py 003.img <offset> pkg                 # extract the pkg
    python3 -I cpio.py pkg/com.avid.00family.macos.installer_0.pkg/Payload payload
