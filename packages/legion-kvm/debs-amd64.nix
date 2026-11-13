# This is a generated file.  Do not modify!
# Following are the Debian packages constituting the closure of: base-passwd dpkg init-system-helpers libc6-dev perl bash dash gzip bzip2 tar grep mawk sed findutils g++ make curl patch locales coreutils util-linux file dpkg-dev pkg-config login passwd sysvinit diff build-essential meson ninja-build pkg-config bison flex python3 python3-mako python3-yaml python3-packaging python3-ply python3-pycparser python3-jinja2 glslang-tools spirv-tools libdrm-dev libelf-dev libexpat1-dev zlib1g-dev libzstd-dev libwayland-dev wayland-protocols libx11-dev libxext-dev libxfixes-dev libxrandr-dev libx11-xcb-dev libxcb-dri3-dev libxcb-present-dev libxcb-randr0-dev libxcb-shm0-dev libxcb-sync-dev libxcb-xfixes0-dev libxshmfence-dev libxxf86vm-dev libudev-dev binutils xz-utils ca-certificates bash dash xdg-user-dirs locales tzdata vulkan-tools xwayland xauth x11-xkb-utils x11-xserver-utils libgl1 libegl1 libgles2 libglx0 libgbm1 libnvidia-egl-gbm1 libvulkan1 mangohud libsdl2-2.0-0 libxkbcommon0 libxcursor1 libxi6 libxcomposite1 libwayland-egl1 libwayland-cursor0 libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 libfontconfig1 fonts-dejavu-core libfreetype6 libdbus-1-3 libgnutls30t64 libldap2 libpng16-16t64 libjpeg62-turbo libtiff6 libvpx9 libudev1 libusb-1.0-0 libopenal1 libunwind8 libcurl4t64 libssl3t64 libasound2t64 libpulse0 libblas3 liblapack3 libpcsclite1 libvdpau1 libva2 libva-drm2 libva-x11-2 libpipewire-0.3-0t64

{ fetchurl }:

[

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/gcc-14-base_14.2.0-19_amd64.deb";
      sha256 = "5b6825de4263824b78c4c51f6476414f3b4e89c2ab63e81dc8b9b5501e867cf6";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libgcc-s1_14.2.0-19_amd64.deb";
      sha256 = "3c71917b490d1a17aed43196a2787a256ecf060526cdb20216a74bedc061b150";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/glibc/libc6_2.41-12+deb13u4_amd64.deb";
      sha256 = "967aa62605721081c3eb2a17650611a792aa802d76a6511d1840242623d204c9";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/c/cdebconf/libdebconfclient0_0.280_amd64.deb";
      sha256 = "25acadc8b394bc86d05df16e70975e523f8f839a7d8d6d5e22c1cafdcef741aa";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pcre2/libpcre2-8-0_10.46-1~deb13u2_amd64.deb";
      sha256 = "1252b96a5bc44bb5db982bef8eb18e54f5047cede2aff641bce4f8e1edb91c3e";
      name = "libpcre2-8-0_10.46-1deb13u2_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libs/libselinux/libselinux1_3.8.1-1_amd64.deb";
      sha256 = "68bb8d32bd8d6d7d2f5952a169db03d1484b46ae1e52abccdec42a19dccea5d5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/base-passwd/base-passwd_3.6.7_amd64.deb";
      sha256 = "cf31c6956ab5f65815d9d9ea1615c4f78ecd2893c31119658248a4756cee83e7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/a/acl/libacl1_2.3.2-2+b1_amd64.deb";
      sha256 = "08074f01e384bc07c0c2d79a58cf4a6523f71cf75d1808101c79617656c9a39d";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/t/tar/tar_1.35+dfsg-3.1_amd64.deb";
      sha256 = "214c02e1aa291076a3147b8a4c4cae02fadf4c67df629186e3e313726faef1de";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/bzip2/libbz2-1.0_1.0.8-6_amd64.deb";
      sha256 = "cba4cda04244b5e481bb15524bc3c983a7d1b6f330013b9b381706a2fcb65310";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xz-utils/liblzma5_5.8.1-1+deb13u1_amd64.deb";
      sha256 = "1cfcc6e0dc36f438a79b6e2189facdb9d150b08f57d190a60e01c98075c7f896";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libm/libmd/libmd0_1.1.0-2+b1_amd64.deb";
      sha256 = "7244ec3839b61fac0c1884fe08aaa040f26e8f1f35f1f5d3482eacefd30d1b44";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libz/libzstd/libzstd1_1.5.7+dfsg-1_amd64.deb";
      sha256 = "2f6a2aeacfc925eba8b00ac9139bc4bfccf8cacb09eb93de067074b26948eef9";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/z/zlib/zlib1g_1.3.dfsg+really1.3.1-1+b1_amd64.deb";
      sha256 = "015be740d6236ad114582dea500c1d907f29e16d6db00566ca32fb68d71ac90d";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/d/dpkg/dpkg_1.22.22_amd64.deb";
      sha256 = "3e800c6d75e8e709007ed1c356e5fa8509a75c1694fb0a1183709abc9cfdc1f3";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/i/init-system-helpers/init-system-helpers_1.69~deb13u1_all.deb";
      sha256 = "addf78073e1cbc5a5508937e11d2571055e29835e00ee8fab52a66775649378f";
      name = "init-system-helpers_1.69deb13u1_all.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/glibc/libc-dev-bin_2.41-12+deb13u4_amd64.deb";
      sha256 = "2c21175d6a8283ed566d154c0c0bc06f60836e53b0b9e1f74c14eac586b68c24";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/linux/linux-libc-dev_7.2.6-1~bpo13+1_all.deb";
      sha256 = "660214942e7f5d99f0a3fad4b8d9523a6643240827e4fcb43173e40d89ad1e97";
      name = "linux-libc-dev_7.2.6-1bpo13+1_all.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcrypt/libcrypt1_4.4.38-1_amd64.deb";
      sha256 = "0ebc144d662e3197982d1bf3a7b8b35ca845e54c68811de0328b1f0d7c67585c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcrypt/libcrypt-dev_4.4.38-1_amd64.deb";
      sha256 = "98e2333aea8d64ca68f9b75c16256d3a05492fd8f9e6dba96adbc6f19e4f5a09";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/r/rpcsvc-proto/rpcsvc-proto_1.4.3-1_amd64.deb";
      sha256 = "32ac0692694f8a34cc90c895f4fc739680fb2ef0e2d4870a68833682bf1c81a3";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/glibc/libc6-dev_2.41-12+deb13u4_amd64.deb";
      sha256 = "1fda734dabcd80b77266a09ab62b0f1e3e16d8091db62899890b2200745632a2";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/perl/perl-base_5.40.1-6+deb13u1_amd64.deb";
      sha256 = "b795464137a0f4d443fc9284f4b93e883fb83883cb533adf300ac660807a352a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/perl/perl-modules-5.40_5.40.1-6+deb13u1_all.deb";
      sha256 = "4c46cdd8f3135aa1c95f07e817f8e5d9be590687441ac1c27e3a8c49400f35ce";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/d/db5.3/libdb5.3t64_5.3.28+dfsg2-9_amd64.deb";
      sha256 = "18d02510ee78b67e4504ba050176797a200ff24214a7cd318082ab60ad7bf3fc";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gdbm/libgdbm6t64_1.24-2_amd64.deb";
      sha256 = "e7b42c68c391e278733adb3c1efdacd24d660862bd7bac0efbc10a91e5696dfc";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gdbm/libgdbm-compat4t64_1.24-2_amd64.deb";
      sha256 = "2cbd43cf2dfbf57ff48188b5d79d29cf7ea8f0dedaa61ab0bcc02eceff50ea01";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/perl/libperl5.40_5.40.1-6+deb13u1_amd64.deb";
      sha256 = "e44777ff47ad248d1debd57e1f96ab5e89061a341008ae39880ba3b5fc15f273";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/perl/perl_5.40.1-6+deb13u1_amd64.deb";
      sha256 = "ef145c247787d6f40dcdefd5b417502484827cde0d555998c17fd5b27ec1e1dd";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/original-awk/original-awk_2025-01-16-1_amd64.deb";
      sha256 = "220e09441ee61bd73cf34502de7505f924b4dc459f4b11ba3c1af8734a5e9254";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/base-files/base-files_13.8+deb13u7_amd64.deb";
      sha256 = "fcd42bb5cb63f7bfc4326a92541247872206d60a192fdff65ca14eb83ed408b9";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/d/debianutils/debianutils_5.23.2_amd64.deb";
      sha256 = "720e43fda316676076498b4224ad3318049deafe60cc7c601011048de03ee97d";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/ncurses/libtinfo6_6.5+20250216-2_amd64.deb";
      sha256 = "8b9f6a7983e9418564e48a627518de4c03917b56efe68d7f3e93bd8fffa1cc10";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/bash/bash_5.2.37-2+b10_amd64.deb";
      sha256 = "2fd7b04f1b7caa29c4e683f5216e6af354a41e3cdcf6e75394d7cda680f9ab82";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/d/dash/dash_0.5.12-12_amd64.deb";
      sha256 = "a8902cb6d8650134764a25fb80aec8589d858ef71ece1680a62e84816c37bb04";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gzip/gzip_1.13-1+deb13u1_amd64.deb";
      sha256 = "74cf12212beee4ab8d473bdc0107abf9e8cef737492198e2f4944a19f142b0ac";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/bzip2/bzip2_1.0.8-6_amd64.deb";
      sha256 = "6b5fbe71f0fc41e85919bc4b3c514e6c47577c5005dbf1f5af6e4a49cc221aab";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/grep/grep_3.11-4_amd64.deb";
      sha256 = "2d78ed07d86a530ebf538f05cb2415f37c8daf908596bc32fc2563cc7e88c55a";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mawk/mawk_1.3.4.20250131-1_amd64.deb";
      sha256 = "ade14470c4dff8921bca6ca8b1ea20eadc0f2178b48caff3c74534b17a633292";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/sed/sed_4.9-2+deb13u1_amd64.deb";
      sha256 = "7071270ed4f6adda55bc4f926347fb847bacaffbdee3dff917bc6006ed7e3775";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/findutils/findutils_4.10.0-3_amd64.deb";
      sha256 = "3edf02b016456b6a98cefdbab99c5ce6f829b786f63affe970badea221aecfc7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gmp/libgmp10_6.3.0+dfsg-3_amd64.deb";
      sha256 = "d0d0265eb01770f17afd0f7c8c0622f80479dcfbbe13653a0debeec61464e622";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/i/isl/libisl23_0.27-1_amd64.deb";
      sha256 = "ac8518042e81c00de1effb72bba7e88ac4ecd488f7ea8b9e3ebc63159cb53b35";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mpfr4/libmpfr6_4.2.2-1_amd64.deb";
      sha256 = "75dddce11dabc7fc543712c33dc27b7f2ee66a111763eb5eac654d010b42cd92";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mpclib3/libmpc3_1.3.1-1+b3_amd64.deb";
      sha256 = "2af0a5c128e03694a41c0b011bd8a958b7297436cdb3a15ddad7866dae8c300b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/cpp-14-x86-64-linux-gnu_14.2.0-19_amd64.deb";
      sha256 = "ef274b5379f5f97fc71619d39ecc84d039d3e184570d207b909c90afaa5d79e0";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/cpp-14_14.2.0-19_amd64.deb";
      sha256 = "3bae5fe03c56c6d021900ab4fb79e35c6f75eee72a73fccc6f28a39db559d6a0";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-defaults/cpp-x86-64-linux-gnu_14.2.0-1_amd64.deb";
      sha256 = "d902f484e38bce59e82efc0df2fe20139a0932ca759ecafdfe6e5b6c72238eb8";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-defaults/cpp_14.2.0-1_amd64.deb";
      sha256 = "a6ba40550aadec80437813e0fce5516574945ff40e72306a5b378c03af3a6544";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libstdc++6_14.2.0-19_amd64.deb";
      sha256 = "ab1fa05837aa7a92aae748fd07a18a35f7d18bb4a71c4724fe2bbf0e32089de0";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libcc1-0_14.2.0-19_amd64.deb";
      sha256 = "2d587e3bfba4aec701946b7ba0c1640b97b6d8dd0a34ba1c70ae85261ecedefa";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/binutils/binutils-common_2.44-3_amd64.deb";
      sha256 = "002da5d23f8757dee97a2c0a40e0e1d4d85a43da094488ee2ee7068d4d3691f9";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/binutils/libsframe1_2.44-3_amd64.deb";
      sha256 = "38f625dfdc582717029ac3a3e97c51d994ec2e7a0e9b230c6b44e40d1276311f";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/binutils/libbinutils_2.44-3_amd64.deb";
      sha256 = "4f4664c8a8f0ad0c8631c39fab02e3d8d86ccc6f4436a1d59f059dbcb0492679";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/binutils/libctf-nobfd0_2.44-3_amd64.deb";
      sha256 = "e280b2be3db6e584500e865c251605b95c346767d87ccb2524e44992048fc657";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/binutils/libctf0_2.44-3_amd64.deb";
      sha256 = "120cafcd93132a276fa92a8fb4cf39b23d14e5a3e348f4f5580638d71ca95ac5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/j/jansson/libjansson4_2.14-2+b3_amd64.deb";
      sha256 = "60707a62fe6c1228c3389b12a13ca4efd76defc5532473e547a29e99cf7d2a6e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/binutils/binutils-x86-64-linux-gnu_2.44-3_amd64.deb";
      sha256 = "e6741ce95ff0f7a131c8d9faa3528ccbbc453078bbc62a97da81340ed7462c53";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libgomp1_14.2.0-19_amd64.deb";
      sha256 = "72b7a1a33c48f3195efeb044111b34ae684b1e640bb6495c832443b798601cd5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libitm1_14.2.0-19_amd64.deb";
      sha256 = "febdb3c528cde1a3abe952e17a1d3cfa7ccaca5b6f506d983d34385dad199490";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libatomic1_14.2.0-19_amd64.deb";
      sha256 = "212b399aae2f7299203d261a57e49372e09565a9a5ea971905f94a3960366c05";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libasan8_14.2.0-19_amd64.deb";
      sha256 = "771899ade7310fe31aa538a509354c33d62bbe4e408b4e5fc1e513988dc42645";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/liblsan0_14.2.0-19_amd64.deb";
      sha256 = "a0df07da76287a45e665d584363dc2a6a1c4e240aee41b8bbc0f67cdff97cd68";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libtsan2_14.2.0-19_amd64.deb";
      sha256 = "529d7f68227d16975076c5f842e8b687faea1b5df8e0dcf62e436d5402844ca5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libubsan1_14.2.0-19_amd64.deb";
      sha256 = "9205a1bef7d6a52ffc06548e0cde169ff303e688c12d9be3a98f734449077e22";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libhwasan0_14.2.0-19_amd64.deb";
      sha256 = "2cdaf797cad8ac30a964ab081370682dd065ae1b0305a0be9d8e0e14cd0657d7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libquadmath0_14.2.0-19_amd64.deb";
      sha256 = "f5b51cf0ece3ec3bb7494d0cdbff3ce715ae00cfb2b6ed787f7db91319d64a7b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libgcc-14-dev_14.2.0-19_amd64.deb";
      sha256 = "ca6f2d36d96b19b3eb71405b0b80134d8c89380b02204a2512e5c58ceb090628";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/gcc-14-x86-64-linux-gnu_14.2.0-19_amd64.deb";
      sha256 = "a17ef039f1ba482051c3efb5c2c24070002e60dd0bd09fd456ec31481a11b725";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/binutils/libgprofng0_2.44-3_amd64.deb";
      sha256 = "0d36d0bde85c467ac6735dded08e19dd30ae1369e3908b9eb48ccc0d6ff66648";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/binutils/binutils_2.44-3_amd64.deb";
      sha256 = "6bc08c02539ba53b5e748142397144c499f9b20b5fa9bb56431545db124addeb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/gcc-14_14.2.0-19_amd64.deb";
      sha256 = "21500408b5019d8d29f70ce58488e2eea469a1adb4b5fd7db45e819b5efcac4e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-defaults/gcc-x86-64-linux-gnu_14.2.0-1_amd64.deb";
      sha256 = "04c28c2760b0094b3d7758154ac095303dd00599b63ebad4086a325b607308b7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-defaults/gcc_14.2.0-1_amd64.deb";
      sha256 = "eee65c41a441c57c05f754ced1b9d093956966a1c7da9938c3ec00d3dc2f905d";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libstdc++-14-dev_14.2.0-19_amd64.deb";
      sha256 = "4b962fac5f1af0bd8b1b3f97e0f47b9d8e9a79e88802143f00ebfbd78ad87a7b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/g++-14-x86-64-linux-gnu_14.2.0-19_amd64.deb";
      sha256 = "c66b009fedd340520279d1af2f91d0668e9f64f0c08fe62179ca1c75e556be58";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/g++-14_14.2.0-19_amd64.deb";
      sha256 = "4706ab29eab3d81e93582b45b229fdedc71f1eec3071996a448cf2c8beb83f3a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-defaults/g++-x86-64-linux-gnu_14.2.0-1_amd64.deb";
      sha256 = "15e10fc3948ec76be8d51b23e75ad9df9c39588c94f1f47059cee02c117c7583";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-defaults/g++_14.2.0-1_amd64.deb";
      sha256 = "f86661c021ab2acb39ceb87315e7c2d4d420fdadc19945d5d589f3953410445c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/make-dfsg/make_4.4.1-2_amd64.deb";
      sha256 = "70a9709e665383b06068ccd423d62ea191b65355f318a25565dbf324b254cec6";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/nghttp3/libnghttp3-9_1.15.0-1~bpo13+1_amd64.deb";
      sha256 = "fa6e52fa0243e91d936c596d4d65978813a65f292deed67d4beff75362c152ae";
      name = "libnghttp3-9_1.15.0-1bpo13+1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/ngtcp2/libngtcp2-16_1.22.1-1~bpo13+1_amd64.deb";
      sha256 = "addfa0f3ca11880689ebd2d6f137b2505df39271eadf11ab63027e91887c6d83";
      name = "libngtcp2-16_1.22.1-1bpo13+1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/brotli/libbrotli1_1.1.0-2+b7_amd64.deb";
      sha256 = "0fb79f88db210afbd69282ab9649e525f393ec6950ca34da1a6b359250b8d7db";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/k/krb5/libkrb5support0_1.21.3-5+deb13u1_amd64.deb";
      sha256 = "3a0acd8b37955c0e102c756b52c97df2a31f67b96453c35dab70df218d309117";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/e/e2fsprogs/libcom-err2_1.47.2-3+b12_amd64.deb";
      sha256 = "bd43e020b8fed399db3eebf098111f10fba4c436fff99ccad72cc7e27c9764ec";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/k/krb5/libk5crypto3_1.21.3-5+deb13u1_amd64.deb";
      sha256 = "7da07ee674b47f1f0be7cc89317c25310086a1f1761217d0f72e6ae2c5a69b84";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/k/keyutils/libkeyutils1_1.6.3-6_amd64.deb";
      sha256 = "0b11ad17be0300b63ad4eeb4c6450fed24d34b7b740f23e5363dcb29ee6d5eba";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/openssl/openssl-provider-legacy_3.5.7-1~deb13u2_amd64.deb";
      sha256 = "f155c8191ae6d41da73d792f4182680aeafeb85c3dd223934ee9fdd115c4f1fa";
      name = "openssl-provider-legacy_3.5.7-1deb13u2_amd64.deb";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/openssl/libssl3t64_3.5.7-1~deb13u2_amd64.deb";
      sha256 = "916f7f40b34a06e6ebfaefcdab331bff458328411da672598f126a760472467d";
      name = "libssl3t64_3.5.7-1deb13u2_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/k/krb5/libkrb5-3_1.21.3-5+deb13u1_amd64.deb";
      sha256 = "47d71d6a7f2e59b9bae5f89602397594805113b95889ad18fa703cd53abafc97";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/k/krb5/libgssapi-krb5-2_1.21.3-5+deb13u1_amd64.deb";
      sha256 = "30847c1fde4240567d7ed3aeab4f655dd591203758b857e85e824045aae70299";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libu/libunistring/libunistring5_1.3-2_amd64.deb";
      sha256 = "6dd3490bef06ea1096f32d10766b7e016cf579bfae8451d1b7df15ce05b8aa46";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libi/libidn2/libidn2-0_2.3.8-2_amd64.deb";
      sha256 = "90b039bcdc4578f8e1c4935adf8dbb525e36a164deefdbbb8c45bac347d48278";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/c/cyrus-sasl2/libsasl2-modules-db_2.1.28+dfsg1-9_amd64.deb";
      sha256 = "a5c38659fbd62c33c6d9bfa2be43e75a572d1818531aad32dd74d0a58cc4bd19";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/c/cyrus-sasl2/libsasl2-2_2.1.28+dfsg1-9_amd64.deb";
      sha256 = "66e49d7ae026811b49a0050f18b0325960a2625ffd1ff60d91b7844a815fa9d2";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/openldap/libldap2_2.6.10+dfsg-1_amd64.deb";
      sha256 = "60069e4a550ca890113fa89d3001417781b18e146ec5d637d31e368dec9909bd";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/nghttp2/libnghttp2-14_1.64.0-1.1+deb13u1_amd64.deb";
      sha256 = "896cb217537c09251fb909b8541349010ac279d802d871e98c06a62a2c67ce2c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/ngtcp2/libngtcp2-crypto-ossl0_1.22.1-1~bpo13+1_amd64.deb";
      sha256 = "403c292ec7672ff8c36fba1d8dbd35f0e17aec941092533c931513adfc0d0dc9";
      name = "libngtcp2-crypto-ossl0_1.22.1-1bpo13+1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libp/libpsl/libpsl5t64_0.21.2-1.1+b1_amd64.deb";
      sha256 = "59d42bb1f9ebc0d1776fe616efb08a7a8568b05982e00f70b03c63863db768ab";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libs/libssh2/libssh2-1t64_1.11.1-1+deb13u2_amd64.deb";
      sha256 = "dbb1024c192d4d292b7cfa902b96076cfe81b56a5eed4fb28da36e8bf543e49a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/c/curl/libcurl4t64_8.21.0-2~bpo13+1_amd64.deb";
      sha256 = "a10997ce6600538f1e67db0bf63243e3310884f536085102fc4dd5b4486282dd";
      name = "libcurl4t64_8.21.0-2bpo13+1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/c/curl/curl_8.21.0-2~bpo13+1_amd64.deb";
      sha256 = "ca52faa49ad03e4287345b169576875a48d432961746b204f029fa9964a382d2";
      name = "curl_8.21.0-2bpo13+1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/patch/patch_2.8-2_amd64.deb";
      sha256 = "80c46a0085b33acc74bf451fddb6a70cb43d4ebcc4a873aec04d8d0a63ffc630";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/glibc/libc-bin_2.41-12+deb13u4_amd64.deb";
      sha256 = "dc8c79647fe3a5f37f72a400414f70263d0212f010ff2c09f990e30d91e38d1c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/glibc/libc-l10n_2.41-12+deb13u4_all.deb";
      sha256 = "dbaa885f5504c67fe43c079f76e2b2b39fcf647ae39880aab3dd66e48f5e772d";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/d/debconf/debconf_1.5.91_all.deb";
      sha256 = "1ddc7e6c5925f748eefb7ca811d98e049f18c158bb21fbc7e122262ce6011e49";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/glibc/locales_2.41-12+deb13u4_all.deb";
      sha256 = "ffc5578d5c2c30ca70d46113908f200a09ab6e5e9eda199463af3285dbbaae8c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/a/attr/libattr1_2.5.2-3_amd64.deb";
      sha256 = "606b5ee12ea2786be607a17f40c1fb5e65c76ceaff66665bdf8f8c6c1b71d1fb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libc/libcap2/libcap2_2.75-10+deb13u1+b3_amd64.deb";
      sha256 = "89fc4d34fc7a28ad6f0fcd0c561ab253b9dedf6f77f5a000b47c276c8295bf67";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/systemd/libsystemd0_257.13-1~deb13u1_amd64.deb";
      sha256 = "ab0d4127b5e46e6f8c015a1db15a62ba9ae274cdefa150083adf90ada0600ea1";
      name = "libsystemd0_257.13-1deb13u1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/c/coreutils/coreutils_9.7-3_amd64.deb";
      sha256 = "1299ab6f9389a288eb2f5f3dd222c26cc777b9a2d5ecb6ee4cbd340cebcdada2";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/a/audit/libaudit-common_4.0.2-2+deb13u1_all.deb";
      sha256 = "b9d32e5ff04fd747aacb7d6b3ebbbbf734ddefb2f1695f0b1b2a4b5e51b1052e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libc/libcap-ng/libcap-ng0_0.8.5-4+b1_amd64.deb";
      sha256 = "20a9e4b0619a3eb2566338223bed135dde5a601eaa2f8fdd5f20b94506addcac";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/a/audit/libaudit1_4.0.2-2+deb13u1_amd64.deb";
      sha256 = "3d1dd3f031a56f01b747e2acc0e14575212580e6fa63d800c44cb0a31f1edfd7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pam/libpam0g_1.7.0-5_amd64.deb";
      sha256 = "4f5bde27d8df2de6ea8990319b42d9974f56a3ba9907ce7296fd0f8964fc9fb1";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pam/libpam-modules-bin_1.7.0-5_amd64.deb";
      sha256 = "cc72066d008444317738e8e931d6131b301466b4e2dd5ef5baa75fb1a45d61a7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pam/libpam-modules_1.7.0-5_amd64.deb";
      sha256 = "9679ade117f8775ac0471f48a92652ab8e8dcda4e2ff06de75158cded9cfd83c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pam/libpam-runtime_1.7.0-5_all.deb";
      sha256 = "b02792c9ed6174db695a653b95ef3629fdac3a73ba1eff1754ab161b5711bfbf";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/u/util-linux/libblkid1_2.41.5-0+deb13u1_amd64.deb";
      sha256 = "81535f3c2c0efc732965907c8749103a0a26377c761622c9ce39b4c92dcde52f";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/sqlite3/libsqlite3-0_3.46.1-7+deb13u2_amd64.deb";
      sha256 = "0a459adaffd901109f7811ab65f58e7a957b4907d05539cf3d1184efdcde0468";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/u/util-linux/liblastlog2-2_2.41.5-0+deb13u1_amd64.deb";
      sha256 = "abb76aecbf51479e6e193873dfddaa1b88667dc0b1db82a11286a67550ba1557";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/u/util-linux/libmount1_2.41.5-0+deb13u1_amd64.deb";
      sha256 = "6d00f45f2e80e078e906e3eedecd3ba6913e39fef49bff361ee583f17f00ec05";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/u/util-linux/libsmartcols1_2.41.5-0+deb13u1_amd64.deb";
      sha256 = "d96bac9c8805685f2734885098a214b82950da6ebb182c27a6b7a124a0323392";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/systemd/libudev1_257.13-1~deb13u1_amd64.deb";
      sha256 = "5d41c284f5a93b05bc7d648b61a02dd2bb9ff05b2261ad1a8b7d96044a0cfa88";
      name = "libudev1_257.13-1deb13u1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/u/util-linux/libuuid1_2.41.5-0+deb13u1_amd64.deb";
      sha256 = "c1bf4c4c3ff48c57fabf93307dfb56996b60cfa33927afc4158b5db36fb2721e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/u/util-linux/util-linux_2.41.5-0+deb13u1_amd64.deb";
      sha256 = "7d5b1176cc3d8cc6b290b3ec17af458f362d9200845f30da22057a8198744430";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/file/libmagic-mgc_5.46-5_amd64.deb";
      sha256 = "1368da7c4c7dd10fb2f9ee3ed8a70801650c0c1d249a4076af15e2ddfbb14b46";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/file/libmagic1t64_5.46-5_amd64.deb";
      sha256 = "53f653873216b135570b42c423ea93825c008ac464780b4578e80ee424237a4e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/file/file_5.46-5_amd64.deb";
      sha256 = "5b980b02a7d91aab9cb50c65ac7e059678a36d36ed626ec52506442f4501a1a7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/d/dpkg/libdpkg-perl_1.22.22_all.deb";
      sha256 = "b41eaeb4879091023f8c1a058510844a244d3d0bd0f437e0e05d58213e36fd9f";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xz-utils/xz-utils_5.8.1-1+deb13u1_amd64.deb";
      sha256 = "9e0a39d95373afdaad3c9dfaab3c8b0beb9a2c4654e6be10b4bcf458509a3217";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/d/dpkg/dpkg-dev_1.22.22_all.deb";
      sha256 = "6d4020421740a70e1fb9c41b07f8bb8306d93aef6fea1a8ce11a1f839921f414";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pkgconf/libpkgconf3_1.8.1-4_amd64.deb";
      sha256 = "85087cd04e57fd4ab7d6e816d348c335047823ab60c78878336b74f07b352ca1";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pkgconf/pkgconf-bin_1.8.1-4_amd64.deb";
      sha256 = "54efef2aef4db5fcb5e0f5b7746465000c6a779b06f3686d0ec3d2a901b20aeb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pkgconf/pkgconf_1.8.1-4_amd64.deb";
      sha256 = "f1fcad470ca3ac80b4a0f4af6f03cd215089473996b07e508b3ee342bbb11af7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pkgconf/pkg-config_1.8.1-4_amd64.deb";
      sha256 = "385209ba52e5c97808bbdc2fc4da22aea9020f96fbab6fbfb144921c4a31d400";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/shadow/login.defs_4.17.4-2_all.deb";
      sha256 = "b4bbb8242cbf5588de7aafeb9d578a3dee1db2891f444ab454fd30bd80ccf2b4";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/u/util-linux/login_4.16.0-2+really2.41.5-0+deb13u1_amd64.deb";
      sha256 = "8fc5869532a73d577c4abb5ed917e048bbd72148702ea1dcadd3817064f3e887";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libb/libbsd/libbsd0_0.12.2-2_amd64.deb";
      sha256 = "e5a85986fa6bec3307ab1bc860736b478b331882bc45e17675a7bdf88eecb43a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libs/libsemanage/libsemanage-common_3.8.1-1_all.deb";
      sha256 = "65375d886749c236bd1da4d9990b7c2469d2fe66019a28e5614f6814376d3dcb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libs/libsepol/libsepol2_3.8.1-1_amd64.deb";
      sha256 = "3595d2d3a6d24695e7953f4f00cdfe6974c9242d9a8dfee8998e77fbf7b2ba09";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libs/libsemanage/libsemanage2_3.8.1-1_amd64.deb";
      sha256 = "f97da7505d17ad3bdd8fc56302256df7e158e5e0d8b02cb766654199cbc406a9";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/shadow/passwd_4.17.4-2_amd64.deb";
      sha256 = "c5eaef41c6947d2888fa3462f787a7e02158b997bd0119154283f425ba57b8b8";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/sysvinit/sysvinit-utils_3.14-4_amd64.deb";
      sha256 = "c7e957360dff89675b491e501b00047cf750695178cabab167c92fc260d358ec";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/i/insserv/insserv_1.26.0-1_amd64.deb";
      sha256 = "c1e71f879de0226d6da7c8bd1deb10bd79e0667f14c3956f9c1275cb3a329d43";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/startpar/startpar_0.66-1_amd64.deb";
      sha256 = "2e7fe320ed88b1d59484f7beb76331589664eed012d9458aa223e09a4a9d6dd8";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/sysvinit/sysv-rc_3.14-4_all.deb";
      sha256 = "05bae4fc83f9063940778429a60f30e844a862822f0cd2a15c51a11fe9841dce";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/sysvinit/initscripts_3.14-4_all.deb";
      sha256 = "989e9bb0f6c7cb5635536c636a038c8aca15513d1f9e9a80682782a3db642d2f";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/u/util-linux/mount_2.41.5-0+deb13u1_amd64.deb";
      sha256 = "eb70a615114ac40123768beb20e302554d5cb7edb33290be7e418ebe1075c878";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/sysvinit/sysvinit-core_3.14-4_amd64.deb";
      sha256 = "2a8fa17f392586715536bf887934326453316d776f114e4b57574c9a064b9b37";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/d/diffutils/diffutils_3.10-4_amd64.deb";
      sha256 = "d3412669f7ae53ba895c3a509620ea7494ec1a36faa204c5215442ced381a479";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/build-essential/build-essential_12.12_amd64.deb";
      sha256 = "a45159aebea0d98d6652ac5a56b7fff164a7733a7dc736b9f8715ca504519d3a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python3.13/libpython3.13-minimal_3.13.5-2+deb13u5_amd64.deb";
      sha256 = "a4aa6a9a8c77f87bfe545e1d14ec42c001d189ace90e3aa75deec882b39dee49";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/e/expat/libexpat1_2.8.3-1~deb13u1_amd64.deb";
      sha256 = "38abe0e710a07688e9c149d74536e67cfee0364bdb64dd6d644c32a1cfad389f";
      name = "libexpat1_2.8.3-1deb13u1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python3.13/python3.13-minimal_3.13.5-2+deb13u5_amd64.deb";
      sha256 = "c1fda9e7b1bf15b2fa75a238d8a8710e142fe14c722fc650c5fc614f078c9073";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/media-types/media-types_13.0.0_all.deb";
      sha256 = "0788e4b0b72db1bcf74a19cb24c3511e7770ad0b341f0f30e361701c3072f53e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/netbase/netbase_6.5_all.deb";
      sha256 = "76bafa92947ebd37b0a6f9ec6570412041f56edebc1c66d323731216d318471e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/t/tzdata/tzdata_2026c-0+deb13u1_all.deb";
      sha256 = "813b9bbbe14ccda2b24617b8bade0ade4d745957e75921766c153d249886bd4c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libf/libffi/libffi8_3.4.8-2_amd64.deb";
      sha256 = "0ebdc340de33333639c3c63874cd4b15ac2e83dfa1ef3053b7eefaf4919f4f68";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/ncurses/libncursesw6_6.5+20250216-2_amd64.deb";
      sha256 = "47baa2e11579583654583a066b69bd5a5d2f22423081f707ed6c0c3ba6d538b7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/r/readline/readline-common_8.2-6_all.deb";
      sha256 = "f77e8aa0bf0de618f11cb0b21658a4ed60f177d63b3cf26d7fc3706b6d0eaaa9";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/r/readline/libreadline8t64_8.2-6_amd64.deb";
      sha256 = "eeadf2b5e755c9f183883feea2d9b5b28560284275d5f54d3e55d0923b1d0967";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python3.13/libpython3.13-stdlib_3.13.5-2+deb13u5_amd64.deb";
      sha256 = "db161322a3481d2c0c3b9a3b9a03c3ab0e2b1718f54b88755fb4a3f939165b84";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python3.13/python3.13_3.13.5-2+deb13u5_amd64.deb";
      sha256 = "460c1fd72845516ac3ce9d1686916f3ab2e4c86f8a9746e14d26243a47e2b98d";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python3-defaults/libpython3-stdlib_3.13.5-1_amd64.deb";
      sha256 = "7e142ed64a81ccdd39714f213467bd365736ef341adb2be11be981f638b9175f";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python3-defaults/python3-minimal_3.13.5-1_amd64.deb";
      sha256 = "a5d2371bebf3689f676e3f3bae800371bcc4392a8a51269e23d528249b399615";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python3-defaults/python3_3.13.5-1_amd64.deb";
      sha256 = "c1388174dc7140e6c19a6dd39f8a0dcb38a835cd66c65644e0dded43d5223cb0";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/ninja-build/ninja-build_1.12.1-1_amd64.deb";
      sha256 = "bc172ce9270bd6fcd6d5335a83ff9d3c7ba0d13ec624cfdfa1b5aa06901dc453";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python-autocommand/python3-autocommand_2.2.2-3_all.deb";
      sha256 = "1e62ac22ff83466228c051c6c2402a40f521646e15b5aa54cf2391206a848bad";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/more-itertools/python3-more-itertools_10.7.0-1_all.deb";
      sha256 = "385d785fa84261838732ec97627b4e95ec7399fc449d8a2aaaef66fb5f961c25";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python-zipp/python3-zipp_3.21.0-1_all.deb";
      sha256 = "6cd0f768a5e5c574c7ae4b9d56603f8399b31de732167007e42fc17decc5cc6a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python-importlib-metadata/python3-importlib-metadata_8.7.0-1_all.deb";
      sha256 = "f895d1f4901176f5e75614bf95b98ccc2a6cd5017ba5ec727b29f281d29be1cd";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python-typing-extensions/python3-typing-extensions_4.13.2-1_all.deb";
      sha256 = "b67662f211c35c17c74a0725bc7c8ffc3b126c650e2a2525593adee06f2bbf69";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python-typeguard/python3-typeguard_4.4.2-1_all.deb";
      sha256 = "81e512101d7ab94e73646b9a8e4fb9b948836e3172dc5719ad3acbcde65bca01";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python-inflect/python3-inflect_7.3.1-2_all.deb";
      sha256 = "6c10dca4d4aa0eb0b4e16e8b62b74a073a8d22be8809c3f61c56b06fdd1451f8";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/j/jaraco.context/python3-jaraco.context_6.0.1-1+deb13u1_all.deb";
      sha256 = "f909ec7b00dd96a1905322acba7cdd2df09747ceddeef6e426a97b33ab227f80";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python-jaraco.functools/python3-jaraco.functools_4.1.0-1_all.deb";
      sha256 = "f5ac3e5f79b6394191d76ea7cde9255d8bae98f639886cb981444128f6545796";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/setuptools/python3-pkg-resources_78.1.1-0.1_all.deb";
      sha256 = "cf8749251172abc945216cf878367f614cf91d3d9a1043ba3bacc5a74e8cc1a8";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/i/importlib-resources/python3-importlib-resources_6.5.2-1_all.deb";
      sha256 = "7f6c49804f85cfbe94dcb51d1c34e64795a475e69ab8f4c33bb6100e8c37fc6f";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/j/jaraco.text/python3-jaraco.text_4.0.0-1_all.deb";
      sha256 = "d5e060c9ba9d5206b53670cf2473681b45030cc6a55d18a8c6d87419a924e502";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/setuptools/python3-setuptools_78.1.1-0.1_all.deb";
      sha256 = "90c4bc8e311873e5b571b407ce6b1fd38195dff77f9de056301a0f950e6df5a5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/meson/meson_1.7.0-1_all.deb";
      sha256 = "e92d04e60e784336883d537755d09b7dcb856809fa318a0931df3898e84ded95";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/m4/m4_1.4.19-8_amd64.deb";
      sha256 = "221b3e224708c1da2a1a88b6824380593579b2254ae7d914afa14cbd5d343334";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/bison/bison_3.8.2+dfsg-1+b2_amd64.deb";
      sha256 = "ce6eb1f7aad18850e32d223a68f54bcbe756d74f138c8ec5460ad9d220f4d335";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/flex/flex_2.6.4-8.2+b4_amd64.deb";
      sha256 = "75f963765232c356d0a2fb70e780dfa9de2425aca036ec60eefb7fc98a2c905b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/markupsafe/python3-markupsafe_2.1.5-1+b3_amd64.deb";
      sha256 = "f82dbd759e6b9c111dc764b3ce7744633d0c97948aaa77294984b80e9db44a24";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mako/python3-mako_1.3.9-1_all.deb";
      sha256 = "03454643ca7c76ffda4a511228b86fee330e1dc9fc5bd9914afe7c5047b991ef";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/liby/libyaml/libyaml-0-2_0.2.5-2_amd64.deb";
      sha256 = "8a5475402801de445a17887bb72d03613565a6a84b216b4b606d1462c613eeb2";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pyyaml/python3-yaml_6.0.2-1+b2_amd64.deb";
      sha256 = "0019c4e7848c83a0d6bcb78cca902b5cdb1714aa6370ba01955b1fed6f667056";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/python-packaging/python3-packaging_25.0-1_all.deb";
      sha256 = "d70c8469f6e9c6105e1ebcd3ebdc963f11dadbeddd89d2d1a2a3cb1c97d2ecbc";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/ply/python3-ply_3.11-9_all.deb";
      sha256 = "d85058c4ec2b77641f7cc413d943be1f412b1b44d4cbe0b174810d37615a7a00";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pycparser/python3-pycparser_2.22-2_all.deb";
      sha256 = "1aa9bac8dac107b96fba3277ee067ef6d10b2ae521bb052841068b5194afd408";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/j/jinja2/python3-jinja2_3.1.6-1_all.deb";
      sha256 = "3271804134e18dbc8dbd146f58399817789373e86a58be44d10ce159cf8c4600";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/spirv-tools/spirv-tools_2025.1~rc1-1_amd64.deb";
      sha256 = "2cc272ef1340cf0b47de6c5fcccaf91574d7a8f4061abb718d6c639463e85aab";
      name = "spirv-tools_2025.1rc1-1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/glslang/glslang-tools_15.1.0+1.4.309.0-1_amd64.deb";
      sha256 = "c3025c4af63244296bc9d466746763c809d3f3f126408fc2c7b07070886a7759";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libd/libdrm/libdrm-common_2.4.124-2_all.deb";
      sha256 = "9a8a6c65c165e9964f106fb4ac710959b5d33e0790227e3ab6b27c4742d1254a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libd/libdrm/libdrm2_2.4.124-2_amd64.deb";
      sha256 = "fe2276901c7cd7b8079de63072d37fe1cbeb4eb001a3bc1f1d662ad89aa0890e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libp/libpciaccess/libpciaccess0_0.17-3+b3_amd64.deb";
      sha256 = "d9a0091071635a84e837051e4813005ac445071731becea28fba4d9806df5252";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libd/libdrm/libdrm-intel1_2.4.124-2_amd64.deb";
      sha256 = "188ab1fd74c838b3c8055d62107351e16a4bb7a25d39c30bbb9aac30ddd37238";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libd/libdrm/libdrm-radeon1_2.4.124-2_amd64.deb";
      sha256 = "7a82b1c88b45235e314a15b71781b47ed472dafbbf697481ec8427079840fc32";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libd/libdrm/libdrm-nouveau2_2.4.124-2_amd64.deb";
      sha256 = "634dcb46487fb2ca267850261291463845ada90b81d16a926ca40d333ce57180";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libd/libdrm/libdrm-amdgpu1_2.4.124-2_amd64.deb";
      sha256 = "c1d97a5e32e2bc68e833b8abeae026b6306198e87ee4396a7ffecd4779caefbf";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libp/libpciaccess/libpciaccess-dev_0.17-3+b3_amd64.deb";
      sha256 = "dfaa687d4ccb943f5b222261a11a1678992bc499abe472d539aa59c4787a0c33";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libd/libdrm/libdrm-dev_2.4.124-2_amd64.deb";
      sha256 = "83b84b1207c4dda3d64ebad7725a7ad237c69c870668db3b01eabad1052f0dcb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/e/elfutils/libelf1t64_0.196-1~bpo13+2_amd64.deb";
      sha256 = "ffcc8ca0db9530597aa4ee4feebf1e3fb3b30c6f38f0d14ed5d9fe593ae5c8ce";
      name = "libelf1t64_0.196-1bpo13+2_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/z/zlib/zlib1g-dev_1.3.dfsg+really1.3.1-1+b1_amd64.deb";
      sha256 = "76ed5c858e1aef38b7be93acce5910e457e77bd6271471b9d05fb42e78826224";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libz/libzstd/libzstd-dev_1.5.7+dfsg-1_amd64.deb";
      sha256 = "de5f8aabcf4cb5cd1b441495ea4c24838e88ecbb30ae22c032a1b3b68a9d6f1e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/e/elfutils/libelf-dev_0.196-1~bpo13+2_amd64.deb";
      sha256 = "e23ef5f6e4b9a6b40721584fd0b73ed3d8a7643fc583136806b50221ca015b99";
      name = "libelf-dev_0.196-1bpo13+2_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/e/expat/libexpat1-dev_2.8.3-1~deb13u1_amd64.deb";
      sha256 = "13f69f5290374c8403d2114b91cc8d0e6bb7b74e9e2512b7e04557546c922749";
      name = "libexpat1-dev_2.8.3-1deb13u1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/w/wayland/libwayland-client0_1.23.1-3_amd64.deb";
      sha256 = "d1607e1db1a7c5378a2e5c6ae7b20f64dc6acf134f953d84a7f5204b74339f33";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/w/wayland/libwayland-server0_1.23.1-3_amd64.deb";
      sha256 = "2967212bd582e0dffca443fdc44f4c660e7368d41f7ee3a7f6314e0c3abfe9ea";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/w/wayland/libwayland-cursor0_1.23.1-3_amd64.deb";
      sha256 = "26fccae2b1228744de0cad6c688550b8d13cd4e8d4ccf0cfdae015634ece673f";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/w/wayland/libwayland-egl1_1.23.1-3_amd64.deb";
      sha256 = "7c5c3429028b39b9432792db08cb218c43891df439ebc648b83ebee676a80ec5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxml2/libxml2_2.12.7+dfsg+really2.9.14-2.1+deb13u3_amd64.deb";
      sha256 = "e0c6b63ce4602a036a526f60fe5e6c1586710688058d98fc1001b9b3147b7efd";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/w/wayland/libwayland-bin_1.23.1-3_amd64.deb";
      sha256 = "9360776a0e973ae3cfb601aa6baa72b855f69109532ec06d5acb727ccc4e003b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libf/libffi/libffi-dev_3.4.8-2_amd64.deb";
      sha256 = "76b2b80193a656733e1408ebec5371334be5fd48eb5f50ab99d6baf6081d0f1b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/w/wayland/libwayland-dev_1.23.1-3_amd64.deb";
      sha256 = "66055b7df9a6c4b15fe0b52a42a76680bb4d0f4d1083800e7cd7ba26e59e68ed";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/w/wayland-protocols/wayland-protocols_1.47-1~bpo13+1_all.deb";
      sha256 = "402b91279c04c62c023883adc8d55931af7ed2d37c755123e3be71373c4ca1f0";
      name = "wayland-protocols_1.47-1bpo13+1_all.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxau/libxau6_1.0.11-1_amd64.deb";
      sha256 = "689a9f0e0ba3e2c65431f864871e303ee904de69dd28abfc462663fae030227f";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxdmcp/libxdmcp6_1.1.5-1_amd64.deb";
      sha256 = "0740dc760916b2008b45417a42a8fd7dd5de370fb57d31373f15034cda8acf0b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb1_1.17.0-2+b1_amd64.deb";
      sha256 = "5c222a72d11b866447da31693254f738430726e3e065a384e82687b2fd2f978b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libx11/libx11-data_1.8.12-1_all.deb";
      sha256 = "c54f87069888f80ba4da586da6147d74c7598ccdd8b90906dbc4271fa414c738";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libx11/libx11-6_1.8.12-1_amd64.deb";
      sha256 = "b5a3fd3bf8c8fd0364bfb9bea00dcba7fc301229bd02dded084632d31f5b0fb3";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xorg-sgml-doctools/xorg-sgml-doctools_1.11-1.1_all.deb";
      sha256 = "168345058319094e475a87ace66f5fb6ae802109650ea8434d672117982b5d0a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xorgproto/x11proto-dev_2024.1-1_all.deb";
      sha256 = "6a6764500eb8171d3cd6d793c09902974f8ea87bd20c68d9eac5f1eeaf3fc407";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxau/libxau-dev_1.0.11-1_amd64.deb";
      sha256 = "1e29410af794a3d3790aab9fa0c1b0ec9324697502e982fce4dcdd4610ce3e8a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxdmcp/libxdmcp-dev_1.1.5-1_amd64.deb";
      sha256 = "bc845297d20cf63388c6b248d9ee169a3890347cb1c29bcd9f771684bf17b528";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xtrans/xtrans-dev_1.4.0-1_all.deb";
      sha256 = "9ce1af9464faee0c679348dd11cdf63934c12e734a64e0903692b0cb5af38e06";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb1-dev_1.17.0-2+b1_amd64.deb";
      sha256 = "669949f8d5dff76616630d839b9047b76af553c62c376458094bd759f8fdb903";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libx11/libx11-dev_1.8.12-1_amd64.deb";
      sha256 = "530de60c9c6dadd997ae7d74eca2a41b25e849373a5ad5dcdb619aa05713d6e0";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxext/libxext6_1.3.4-1+b3_amd64.deb";
      sha256 = "fc618ec40465e5ce48622606299cb47833efc3fb235ba15543b81f850722f443";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxext/libxext-dev_1.3.4-1+b3_amd64.deb";
      sha256 = "e6bd898976d762a6955ec465870e7f12a3b149f4c5b231b0687e293ed5726532";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxfixes/libxfixes3_6.0.0-2+b4_amd64.deb";
      sha256 = "3fdd95d86d8e9d63e11f52070935c8f9f912c36aa3b17338d969f7685f3ed4fb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxfixes/libxfixes-dev_6.0.0-2+b4_amd64.deb";
      sha256 = "1070e0721765992c5355a9585f6eae9e0d11437a7d2b4a2c28123e6e5b0c0b2f";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxrender/libxrender1_0.9.12-1_amd64.deb";
      sha256 = "9d042dfd5e613be1e02e6ddd0c5c4adef19c5eb08f6db838c2eba672c496dca4";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxrandr/libxrandr2_1.5.4-1+b3_amd64.deb";
      sha256 = "11e3490de93a8bbee3daba719cb8e1325a26fb3c125525c34bdcb7deb05eb9b2";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxrender/libxrender-dev_0.9.12-1_amd64.deb";
      sha256 = "55121741c44e03cbeb03dabb5721ded1341c987f055d7cae991de7431c9edfa6";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxrandr/libxrandr-dev_1.5.4-1+b3_amd64.deb";
      sha256 = "e408e4f8c77135725e9055d445635587225839a929d348c04b85adfa84bdefb1";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libx11/libx11-xcb1_1.8.12-1_amd64.deb";
      sha256 = "e05f94d21a932fba5b09b9b13d99df776b155d3bc792c0e294451df9ffe1ba25";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libx11/libx11-xcb-dev_1.8.12-1_amd64.deb";
      sha256 = "c0ff9bf67c5bc10364bc59053d31866304f2b3d5be700a5316ebf6a4a33920c4";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-dri3-0_1.17.0-2+b1_amd64.deb";
      sha256 = "f446d42fb5fcebbb3e347368ba83616769fdb271d85b2f49048e337f3163d267";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-dri3-dev_1.17.0-2+b1_amd64.deb";
      sha256 = "08069d76b5d51e80ff24b7a4b20f7136a601b0842be6570f1b582c592e90c03b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-present0_1.17.0-2+b1_amd64.deb";
      sha256 = "db95ea4630c55bd7f3281cb60ccf75b1627ef2f4399e1939f8f6161e584a92fb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-randr0_1.17.0-2+b1_amd64.deb";
      sha256 = "f5d9fe5fdf797918f81f0abf6cfd4270bd54659540cddb4da709ab7154523214";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-render0_1.17.0-2+b1_amd64.deb";
      sha256 = "7f6e36978e0f70a590fbad4042a692c70b50ca7cbcdc53fa7e9d9ab87933acc6";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-render0-dev_1.17.0-2+b1_amd64.deb";
      sha256 = "cf76ecebf0dc0adc5f24bcd024e6eda69afe0c89fd38953c5ad363416fe03add";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-randr0-dev_1.17.0-2+b1_amd64.deb";
      sha256 = "5f2e27d6d79c82689e652f60a09f52022196242292abc15e4e3a0ef55c429b15";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-xfixes0_1.17.0-2+b1_amd64.deb";
      sha256 = "f9c1aafc18bf9e4662e34bbaf3bb00f1f4e8c2fc1dd786fdfb6cb9cb6c64fae7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-shape0_1.17.0-2+b1_amd64.deb";
      sha256 = "eb94a643d66714929053e78ff8f38a90ce8af4ed854e3cbca0b14f8bbccc7bfc";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-shape0-dev_1.17.0-2+b1_amd64.deb";
      sha256 = "28e12725fa7fa8905199a21fa227ee068332c1259f1c6e8371dff7d917b8ad96";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-xfixes0-dev_1.17.0-2+b1_amd64.deb";
      sha256 = "3b6ca65d5ab9c6049d4aae731f93302fefafe8dd3de601b78b9dcfb59a63f2db";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-sync1_1.17.0-2+b1_amd64.deb";
      sha256 = "0ce4770ed1505be9ddc6473045e4662d062aff2f3077ee684265f01cfb543559";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-sync-dev_1.17.0-2+b1_amd64.deb";
      sha256 = "5ac93aa77d9c39145de0898c0bd19a400efce070f14fab906d506106730c2a3d";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-present-dev_1.17.0-2+b1_amd64.deb";
      sha256 = "46cc01f1e4e26692c7f532d74413d8e79dc7c9644dac6ef4b64d66f55d3a789a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-shm0_1.17.0-2+b1_amd64.deb";
      sha256 = "d1777a813f484e89f3dcaadd1d5f2b1a13e9313b6bf70eded16d8ce743208fef";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-shm0-dev_1.17.0-2+b1_amd64.deb";
      sha256 = "f8f9d2817695fdc74e3a2582c0c2d7d571e44f379ac30926438fae6b9760736d";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxshmfence/libxshmfence1_1.3.3-1_amd64.deb";
      sha256 = "7b339e9e5b2349723d35af4df89bcc7aa456bbdf8ba1754358f9b44c3fe1f964";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxshmfence/libxshmfence-dev_1.3.3-1_amd64.deb";
      sha256 = "52a0a738552cd340c6cf237341e708ceecb1a2547307131d214c20de816be423";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxxf86vm/libxxf86vm1_1.1.4-1+b4_amd64.deb";
      sha256 = "f9f8487e536293e7ecf91fe7feb14e97e02a3aa652e207c661442dce775d3b14";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xorgproto/x11proto-xf86vidmode-dev_2024.1-1_all.deb";
      sha256 = "ef611c147e699a3db090d811b649442d2b08cb4274f5e0d407fff8ded4d0e28d";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxxf86vm/libxxf86vm-dev_1.1.4-1+b4_amd64.deb";
      sha256 = "cba80fa53162a7c3e3e4e8ec519c2fc3b19c2b4b4d4b22641b7236caeb5edba4";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libc/libcap2/libcap-dev_2.75-10+deb13u1+b3_amd64.deb";
      sha256 = "795983cf2cbc2e12e9440383d701229966c35bc40712ccbfd03e5c93d9af619d";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/systemd/libudev-dev_257.13-1~deb13u1_amd64.deb";
      sha256 = "73c3ed98a435ec420b327ef267d89ece81bf23c2c19391265bb4f261cbf5d558";
      name = "libudev-dev_257.13-1deb13u1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/openssl/openssl_3.5.7-1~deb13u2_amd64.deb";
      sha256 = "4ff006f431d8c2e69fa736885a3b6e779f2448535f69dbde821d9f0ff87ad8ea";
      name = "openssl_3.5.7-1deb13u2_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/c/ca-certificates/ca-certificates_20250419_all.deb";
      sha256 = "ef590f89563aa4b46c8260d49d1cea0fc1b181d19e8df3782694706adf05c184";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xdg-user-dirs/xdg-user-dirs_0.18-2_amd64.deb";
      sha256 = "d3be3c7315722fe58921839f8bbf962e638540f2936627acc29464e63feded95";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/v/vulkan-loader/libvulkan1_1.4.309.0-1_amd64.deb";
      sha256 = "f47da79cd140264fe21cceb08bc87a71bc7fec05819e4a421f3f518d21101a37";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/v/vulkan-tools/vulkan-tools_1.4.304.0+dfsg1-1_amd64.deb";
      sha256 = "742d1cd78c333a94b8214e21ba455d47884dc32f110016ffe6998cf88f2a2f94";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/lsb/lsb-base_11.6_all.deb";
      sha256 = "f8bedd167280e76636df3a1bc023cd2906d458916c1af4c1d7912c5b971fc642";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xorg/x11-common_7.7+24+deb13u1_all.deb";
      sha256 = "57a981938506b26dc552f19cafeaa8c04e9b59dc7508509151f8507a9d4e5f24";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xkeyboard-config/xkb-data_2.42-1_all.deb";
      sha256 = "196ff18533382f64e057ea49df2bb486bd4275a4cc0917361edb560b8756dada";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libi/libice/libice6_1.1.1-1_amd64.deb";
      sha256 = "38185997162793b5dfb768644badc57852879784a2f9d83c6c4e47efa5e36698";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libs/libsm/libsm6_1.2.6-1_amd64.deb";
      sha256 = "03038b3002e6f44322554e335d60d8ff87acfcf2e21c904b6866610a9913ee00";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxt/libxt6t64_1.2.1-1.2+b2_amd64.deb";
      sha256 = "a1f4557c03113681ee24863495adc244cecec95fe3ab7256ce76e87320157300";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxmu/libxmu6_1.1.3-3+b4_amd64.deb";
      sha256 = "cfdf1dee8f9abd87f503222fc8b04a30ce820fb1255247b7c3a28ff9c244431a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxpm/libxpm4_3.5.17-1+deb13u1_amd64.deb";
      sha256 = "d2f8933b552e7a282bbc32bc7545628195c4a3692a20ad0e232cc5fee9130790";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxaw/libxaw7_1.0.16-1_amd64.deb";
      sha256 = "e79f3ab51ecbbfd3414a0568a8947ac59a29c30d631e6c7b6e07ea46e688c047";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxkbfile/libxkbfile1_1.1.0-1+b4_amd64.deb";
      sha256 = "989b61e0eb7f1f99d0e969a5957e9a857a95941d5c0e86d5e2b502008b4ac28e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/x11-xkb-utils/x11-xkb-utils_7.7+9_amd64.deb";
      sha256 = "745e29c79bb435d057cdbf8bb59a35fa33e818e566cb754674f44d381ccd4317";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xorg-server/xserver-common_21.1.16-1.3+deb13u3_all.deb";
      sha256 = "dc1d37303c103b23c40cd1ea694c5c6561e0e8dc1734a73c7a0ae0ef080e7fcc";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libd/libdecor-0/libdecor-0-0_0.2.2-2_amd64.deb";
      sha256 = "e4f228a9d4a38af23fab00f8e20219790b567e2e1f7804b3a215a26294350f82";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libe/libepoxy/libepoxy0_1.5.10-2_amd64.deb";
      sha256 = "4c4c8024f2175086de65bca9fdc3fbb967f2863ebf249d489c66d0c8103dd3a3";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libe/libedit/libedit2_3.1-20250104-1_amd64.deb";
      sha256 = "b002ea172b9c1e34a67bc497c523c67bb74c3f0a4e98113cb083990a1f1d3bfe";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/z/z3/libz3-4_4.13.3-1_amd64.deb";
      sha256 = "71383373523ef62d47eccf660cf6535c3febcbb3f88e54cb7a43124014b57359";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/llvm-toolchain-19/libllvm19_19.1.7-3+b1_amd64.deb";
      sha256 = "db0d614d61345ca710fb73e75105f1ec6e38898fa7b3aa99fa7eb7d8b0a11d57";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/lm-sensors/libsensors-config_3.6.2-2_all.deb";
      sha256 = "3056da80c7d963af795dab480ab6f6f4b154ad4ac39f522dc52d17c834fea253";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/lm-sensors/libsensors5_3.6.2-2_amd64.deb";
      sha256 = "f0a994a6d7cfa695dea5343d0d1ba7eed796c0ad920c7282998b95f60049c4f6";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mesa/mesa-libgallium_26.1.6-1~bpo13+1_amd64.deb";
      sha256 = "059b19b15ed2fc684e9c03449a4821de0470fe791b947c5d10d4605da1804ac1";
      name = "mesa-libgallium_26.1.6-1bpo13+1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mesa/libgbm1_26.1.6-1~bpo13+1_amd64.deb";
      sha256 = "cfe9a2d49fe55618f921e7ca02e41241376ba843d598f209bfbb65e6058c49a8";
      name = "libgbm1_26.1.6-1bpo13+1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libg/libgpg-error/libgpg-error0_1.51-4_amd64.deb";
      sha256 = "22b95570fd41c113ef6f5651563b4d748292844baab1278a46eb940c1dec2322";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libg/libgcrypt20/libgcrypt20_1.11.0-7+deb13u1_amd64.deb";
      sha256 = "f0eb41f8cb40896e0822e9ab65611e8383c12b721c76c54764f744abb4a8c247";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libg/libglvnd/libglvnd0_1.7.0-1+b2_amd64.deb";
      sha256 = "887f74008166549ce9e100c906aa937e95d6e5ce1c8d86efe8c95fd953359b9c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mesa/libgl1-mesa-dri_26.1.6-1~bpo13+1_amd64.deb";
      sha256 = "489f584bab1b3dcf09928a6e918e84c33296340f778286efde6d47357de800c1";
      name = "libgl1-mesa-dri_26.1.6-1bpo13+1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-glx0_1.17.0-2+b1_amd64.deb";
      sha256 = "cc59a3fa1c4ce376c3a32798179950810bd7b9be9a35bc76de1f5b5e7cc3925e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mesa/libglx-mesa0_26.1.6-1~bpo13+1_amd64.deb";
      sha256 = "d6997367ca79b56b882f77d859f73b075c29c975f0f5ead667269eb48cc733be";
      name = "libglx-mesa0_26.1.6-1bpo13+1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libg/libglvnd/libglx0_1.7.0-1+b2_amd64.deb";
      sha256 = "2721fdca0fe3bd963cb39482eabc253af52b88f4a7f6dbb69e475549daf5af3b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libg/libglvnd/libgl1_1.7.0-1+b2_amd64.deb";
      sha256 = "87fa2f6e5abaed4ed385fac879c8dd735af719ee2300222d901793c66e041678";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pixman/libpixman-1-0_0.44.0-3_amd64.deb";
      sha256 = "3862c87596f6b4b60fc916395fd69aa10af28a875a8e5c081a8cf30ddd120bd6";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libt/libtirpc/libtirpc-common_1.3.6+ds-1_all.deb";
      sha256 = "300f582e2c9151a8d329568c705cadc76252c417147312fe331c4560d2c7a6c3";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libt/libtirpc/libtirpc3t64_1.3.6+ds-1_amd64.deb";
      sha256 = "ef4536c09bf5063554310e22d586ae90990100ba66d2fe7c35660e9e658913b6";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcvt/libxcvt0_0.1.3-1_amd64.deb";
      sha256 = "0faccb95f5d306fc30c8b128572b92ff97bf59c547f1f8a46b57e0b4c6dd045b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libf/libfontenc/libfontenc1_1.1.8-1+b2_amd64.deb";
      sha256 = "49f7330e1bbe3f48946fee5c07870df660374f9f77b378840d6edf1a3b3444cd";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libp/libpng1.6/libpng16-16t64_1.6.48-1+deb13u5_amd64.deb";
      sha256 = "2465b4e9fa85cff54dc10a6da3e64074d8d9292c86e4a8f989b809d6b158e97e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/freetype/libfreetype6_2.13.3+dfsg-1+deb13u1_amd64.deb";
      sha256 = "e4947f3291528f03d574f2b01d5c5fc45c58c47480f32888a5cdf0f231ab584e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxfont/libxfont2_2.0.6-1+deb13u1_amd64.deb";
      sha256 = "79a7f56e4a0c7b1defa706c7b1f3076f7d80aaeea9de253b2a87406253319681";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xwayland/xwayland_24.1.6-1_amd64.deb";
      sha256 = "7e51a144e858d5be7e91d6644c2758a618e425c7222234d2e8f059e5aba6c1f5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxmu/libxmuu1_1.1.3-3+b4_amd64.deb";
      sha256 = "6b5f537905421599e962a8cec68c84f06d506e143fc70b0b570380b3c4901678";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xauth/xauth_1.1.2-1.1_amd64.deb";
      sha256 = "14687bc8e3af350738f61e5a872bcdd83725694cb09d448d75077abd6249679a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcursor/libxcursor1_1.2.3-1_amd64.deb";
      sha256 = "bb0dbf58b804faaa74ed9efdae61c4b14bb0b4855680798f63e5ca6a4954976b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxi/libxi6_1.8.2-1_amd64.deb";
      sha256 = "093d0903f35bb7a9f6815180ee040e6951fecf9b66c128cd72f064710210606e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/x11-xserver-utils/x11-xserver-utils_7.7+11_amd64.deb";
      sha256 = "71819f316a8f141e2e9b69d871720b854c07b86d79923200c7eafa306bffbd36";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mesa/libegl-mesa0_26.1.6-1~bpo13+1_amd64.deb";
      sha256 = "0d175df6a4fac09eeedfaa9326da1c05c0e8a1911aa413281eb3e3a64ec09b28";
      name = "libegl-mesa0_26.1.6-1bpo13+1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libg/libglvnd/libegl1_1.7.0-1+b2_amd64.deb";
      sha256 = "62e7bc8ccd47a60e55aad17f83d8d474310d782eb8589bbce2ab714c31712406";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libg/libglvnd/libgles2_1.7.0-1+b2_amd64.deb";
      sha256 = "e12c18aa77939d122ee1dea520ba0440b97dc19200b7396e03dff03a3ece74c1";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/contrib/n/nvidia-egl-gbm/libnvidia-egl-gbm1_1.1.2.1-1_amd64.deb";
      sha256 = "5601d49eed470660c8bc794d6ee1e134d2e69012ee2e562b28a5b626a90f2e41";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/fmtlib/libfmt10_10.1.1+ds1-4_amd64.deb";
      sha256 = "da77a5254e5c7cdac6ecf6f8f21a9cc93d64392765f0f0a4dd06805238950fbe";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/spdlog/libspdlog1.15_1.15.2+ds-2_amd64.deb";
      sha256 = "c0e95528c3e04e9e69493c2f875ac3e1477a59ddbd82b2cfdeb2fcf47468ac45";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxkbcommon/libxkbcommon0_1.13.1-1~bpo13+1_amd64.deb";
      sha256 = "55c94c70edbf695e26de90841c39af2a4c47f0796fdb25a461cdb2017540f3cd";
      name = "libxkbcommon0_1.13.1-1bpo13+1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mangohud/mangohud_0.7.2-2_amd64.deb";
      sha256 = "051f63434b463aff8010532d67c549550ef5b621579d9d5d5be8b3922fc5413a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/a/alsa-lib/libasound2-data_1.2.16.1-1~bpo13+1_all.deb";
      sha256 = "5555829e8de7788f6aca3580c1d13d7d3b22265b493d6593f12c94d546432cc7";
      name = "libasound2-data_1.2.16.1-1bpo13+1_all.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/a/alsa-lib/libasound2t64_1.2.16.1-1~bpo13+1_amd64.deb";
      sha256 = "04fde38ba52dc1bfc15d6668ba481b4d21ee4f0559586afb11d9025a672242e9";
      name = "libasound2t64_1.2.16.1-1bpo13+1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/liba/libasyncns/libasyncns0_0.8-6+b5_amd64.deb";
      sha256 = "e7958777b0e3586349c57ac759a95b68f80d28e5bd1c4225705198b39b436115";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/d/dbus/libdbus-1-3_1.16.2-2_amd64.deb";
      sha256 = "bbcb711daff7e104b5f80f9b05475b6142674bfe65518a36a56e96a91068a3f5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libo/libogg/libogg0_1.3.5-3+b2_amd64.deb";
      sha256 = "911aec914f5bda0788164ff8068b682537378bf8d407b1d6c1b377522f96b83b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/flac/libflac14_1.5.0+ds-2_amd64.deb";
      sha256 = "658b9f77d35638caf75dfaea4f6d5cde196104d5662f0776e23d7cc450bd4cb5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/lame/libmp3lame0_3.100-6+b3_amd64.deb";
      sha256 = "3867319c9fbbc8cc25f2d1dc1d75d13548c84c37fa709c1ac9ca02ac051b63ab";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mpg123/libmpg123-0t64_1.32.10-1+deb13u1_amd64.deb";
      sha256 = "31fa6ef638f1fdbe198faee0b6fe50d9dd468077f8247cc3dbf6b2250abb6101";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/opus/libopus0_1.5.2-2_amd64.deb";
      sha256 = "794056db33d71b2ac4bd8b5a4eb23b627bcb8a49d123c33b6e841a996253a067";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libv/libvorbis/libvorbis0a_1.3.7-3_amd64.deb";
      sha256 = "0465f7f602f7b00965e58e7273b5876060ab7946f0452a9f95d979046932cc42";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libv/libvorbis/libvorbisenc2_1.3.7-3_amd64.deb";
      sha256 = "5fbbf06a5b196235aa2753cd12bbe7f843328571d368f15b1c337578e29f73a2";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libs/libsndfile/libsndfile1_1.2.2-2+deb13u1_amd64.deb";
      sha256 = "d92263a045554e6f39c6b1c2ee4cca44a3248d9b9339301ff195969bf84b75eb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pulseaudio/libpulse0_17.0+dfsg1-2+b1_amd64.deb";
      sha256 = "786aca79119cb249562708fd24dcdf817604cfe75bbfcb8cda3464042e17f40e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libs/libsamplerate/libsamplerate0_0.2.2-4+b2_amd64.deb";
      sha256 = "2665417fa996c1e249dbaa65c32305ac666e5ae865fad0f109b629935ec0bd18";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxss/libxss1_1.2.3-1+b3_amd64.deb";
      sha256 = "302d4a97800429fa0d67ae2e0e8e3adc1228b12d25d3d3cca6c9d24eeff40a6c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libs/libsdl2/libsdl2-2.0-0_2.32.4+dfsg-1_amd64.deb";
      sha256 = "c61af1033d79fa6a393c49fac987165876de8ff27ebbd6a36cf19f5fc84d7a7a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcomposite/libxcomposite1_0.4.6-1_amd64.deb";
      sha256 = "20e3c1d9b2135f0c8c4246a9fd26a51a57d5850c3b36ecc173c45d6be7328af3";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/glib2.0/libglib2.0-0t64_2.84.4-3~deb13u5_amd64.deb";
      sha256 = "e2baf92c57d1db1753e5781a61450d9a01e7833c7bd2dfe87776a6811c11ecc2";
      name = "libglib2.0-0t64_2.84.4-3deb13u5_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libc/libcap2/libcap2-bin_2.75-10+deb13u1+b3_amd64.deb";
      sha256 = "6404b8ee315ce3eb8e273981650e419ff0e91aed5213d4975a6895f98944ea80";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gstreamer1.0/libgstreamer1.0-0_1.26.2-2_amd64.deb";
      sha256 = "08b463307fbde5496a346b1bb300b465cd22bd326f6f4634f482bf441af28a9b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/orc/liborc-0.4-0t64_0.4.41-1_amd64.deb";
      sha256 = "5b9afe78be0dd71399c0d4d7e5f26beb6ddf207279997942d8280be1b20bd58c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/i/iso-codes/iso-codes_4.18.0-1_all.deb";
      sha256 = "969582afb02fd3f0833a666b2112931a999c4f6b23e7fe514f8051dfd7672a45";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gst-plugins-base1.0/libgstreamer-plugins-base1.0-0_1.26.2-1+deb13u1_amd64.deb";
      sha256 = "a20aedb3f89c162b4859cec37076f4eba54b0bcc7e5cb254a26cc4a877a88a1e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/fonts-dejavu/fonts-dejavu-mono_2.37-8_all.deb";
      sha256 = "3003e98a5debfdeadc7040a7f715fe9fe6fb67f68deacf6049b54e30f07fc014";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/fonts-dejavu/fonts-dejavu-core_2.37-8_all.deb";
      sha256 = "86635b3d25b3655fc11cb3ecc3af59f0bf19643b02b94f2de48bd10253cdba12";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/fontconfig/fontconfig-config_2.15.0-2.3_amd64.deb";
      sha256 = "0475c00d02660c07a15085051818625331bb502e053242106aaaa1f2ddb41225";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/fontconfig/libfontconfig1_2.15.0-2.3_amd64.deb";
      sha256 = "7ae91ec59857cc8e375eb2bdd371a4a69daea38f7787d06d474a847867d852b1";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/nettle/libnettle8t64_3.10.1-1_amd64.deb";
      sha256 = "1b03d4a9cd9c8143ba50fe6396f36937e901a317d492d179f4596862c1731cfe";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/nettle/libhogweed6t64_3.10.1-1_amd64.deb";
      sha256 = "b059ed155115ac09da295322de48ee1ed58ef5fa45edcc9e12ff0e94636ef25f";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/p11-kit/libp11-kit0_0.25.5-3_amd64.deb";
      sha256 = "784bf2063e166c8bc851a32623b74ebd85c499043a9d57c5bbd64fa63447f45a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libt/libtasn1-6/libtasn1-6_4.20.0-2+deb13u1_amd64.deb";
      sha256 = "23fec6e06583ce2bad9b2c04c9b485e90440e259b1abf8677cd80d3ce60831ad";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gnutls28/libgnutls30t64_3.8.9-3+deb13u4_amd64.deb";
      sha256 = "18a8bdfd91c7e3bcb01719d55a2b56849c7160b34f1f52b1c4fdfdd41bf1352b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libj/libjpeg-turbo/libjpeg62-turbo_2.1.5-4_amd64.deb";
      sha256 = "5504299ad0e3c0a9ca9f962a68a650a040db52f9f416a109e74df48d55601d3f";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libd/libdeflate/libdeflate0_1.23-2_amd64.deb";
      sha256 = "5fe37fb79d53f5c91da6ba3ac4c1a8453e1f2b1ff0e0ea45189c5338bbfdbf82";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/j/jbigkit/libjbig0_2.1-6.1+b2_amd64.deb";
      sha256 = "95cbc44561651e1b3385454df08e8f2efe84498f6963a85259be2cc2fe798709";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/lerc/liblerc4_4.0.0+ds-5_amd64.deb";
      sha256 = "2e0c13c0ddbde12968c2c713c2e0474a5b78e90d5216031256a725e8c76aa31c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libw/libwebp/libsharpyuv0_1.5.0-0.1_amd64.deb";
      sha256 = "51934833d909588f7761fd84362114e90d8d2d38af57edf5df5c4a705e037547";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libw/libwebp/libwebp7_1.5.0-0.1_amd64.deb";
      sha256 = "c749744b04abdd1426b0c7718e516362c03a557c5151662092d6d4f2cef6e7c1";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/t/tiff/libtiff6_4.7.0-3+deb13u3_amd64.deb";
      sha256 = "6bb2038f36817ae1ee6d33df03917b21835dcc2e0f3e3e80a71390e83c171173";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libv/libvpx/libvpx9_1.15.0-2.1+deb13u1_amd64.deb";
      sha256 = "5c2baac5c97a1fe01c4f0a2216743b901dc72437351e7451725a394c08037bcc";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libu/libusb-1.0/libusb-1.0-0_1.0.28-1_amd64.deb";
      sha256 = "bb6467a002915c4ac464aa1b22204907951a30e43bcb86596ebd3539e84458e9";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/openal-soft/libopenal-data_1.24.2-1_all.deb";
      sha256 = "003fb223f6ccd387adc28357021c243c604591806afb84dc46e906b911d8de38";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/openal-soft/libopenal1_1.24.2-1_amd64.deb";
      sha256 = "7b888c0854bdf8e61fb000aa2816ea5ed76cf52da85dba94e463cce5e182662d";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libu/libunwind/libunwind8_1.8.1-0.1_amd64.deb";
      sha256 = "db21a86dd05c93413f0ef36282a9c64d32410d240f332273a53be1408bec1f62";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/lapack/libblas3_3.12.1-6_amd64.deb";
      sha256 = "4af245ecafc30bfa1de9d20af02fec96654ead2f06b1dac40cb03fc9eb0bfbe6";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libgfortran5_14.2.0-19_amd64.deb";
      sha256 = "11b62b53f4704de557e44b510e18a1a2106bcd9a3fc31a475a45952a9aa3dbb2";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/lapack/liblapack3_3.12.1-6_amd64.deb";
      sha256 = "abfc59c8410beee738617bb6daf86b295e45ec0bd08cc0e97bfecc3cfa40fe75";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pcsc-lite/libpcsclite1_2.3.3-1_amd64.deb";
      sha256 = "a8bc4725549060d1e696d358e32a3699d947d5381871553a290389830bebccbd";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libv/libvdpau/libvdpau1_1.5-3+b1_amd64.deb";
      sha256 = "7c872493296cc8ce829ab38a68b5e51c351466a5fd0daf485984c829282a94e3";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libv/libva/libva2_2.22.0-3_amd64.deb";
      sha256 = "b76bdd330de47a826698aaed10f53435b703e9a7d4415dd68269c97709f46a9b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libv/libva/libva-drm2_2.22.0-3_amd64.deb";
      sha256 = "5dce5007ddc0ce87a61db4d71476ce1a5a135737b5185ce2e8b7067342fcafc6";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libv/libva/libva-x11-2_2.22.0-3_amd64.deb";
      sha256 = "97baabc9ae8dfbe718ca80543dc7337d330dd17e2a59138bf42a66a35d59309b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libe/libebur128/libebur128-1_1.2.6-1+b2_amd64.deb";
      sha256 = "ffeea31cb2a88deee3cb76ac04b8a4d4aa3d9e3e7ca3ca8485b0eefc6f3ba26f";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/fftw3/libfftw3-single3_3.3.10-2+b1_amd64.deb";
      sha256 = "cb1910b561a4c475a8005ae1b604d1f5fd9d22114292f45e258ce4a160300e01";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/serd/libserd-0-0_0.32.4-1_amd64.deb";
      sha256 = "a2e1097666c09bf2fce41bff40b8d4cfb8c3c419da99fcb746ea175c5d48fcd5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/z/zix/libzix-0-0_0.6.2-1_amd64.deb";
      sha256 = "896d3b244020120b17a21ded38508582ee861ffa90fc0fb0fd539e27698a96b6";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/sord/libsord-0-0_0.16.18-1_amd64.deb";
      sha256 = "cbb4167b1a85cfec94faa9f85666ee382a8bc79ce93f5d7457514e8334299e52";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/sratom/libsratom-0-0_0.6.18-1_amd64.deb";
      sha256 = "63195bd9233678ed397cfded0aae85d85cf2584ff7c638b34013ca34544962d7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/lilv/liblilv-0-0_0.24.26-1_amd64.deb";
      sha256 = "71f03560980b7c7f89ada7bd49ac3239166db770b2fa752b13d67abbd98ce8bc";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libm/libmysofa/libmysofa1_1.3.3+dfsg-1_amd64.deb";
      sha256 = "27c71e7a0cb7b4d9a683b4ad721d65f11ff1d83823873ee28ac892078bcdb0a1";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/c/cpuinfo/libcpuinfo0_0.0~git20250327.39ea79a-1_amd64.deb";
      sha256 = "e0cc014fe6e6ffb5c9a353ffa5af4c118e0010de419d8454c42256f9d2a52b21";
      name = "libcpuinfo0_0.0git20250327.39ea79a-1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/onednn/libdnnl3.6_3.7.2+ds-2_amd64.deb";
      sha256 = "92cd85c52b74a33101e80bdbe0a2bf4b9aedd8a348688da5aae76fa7b7ba5738";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/protobuf/libprotobuf32t64_3.21.12-11+deb13u1_amd64.deb";
      sha256 = "38c43ec79a043d2b2659fed321725049a7e457096a66691cf6eb0d3a1a8f0e85";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/onnx/libonnx1t64_1.17.0-3+b1_amd64.deb";
      sha256 = "11c88c9928bdc7b12d6711facb00c1f6a6c4aa9a4b8f0c5d7d088abfe3b4dfa9";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pthreadpool/libpthreadpool0_0.0~git20240616.560c60d-1_amd64.deb";
      sha256 = "b9c134c4b499a41c31799751be1932428fb94a042907619a4b94141207b69ff1";
      name = "libpthreadpool0_0.0git20240616.560c60d-1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/a/abseil/libabsl20240722_20240722.0-4_amd64.deb";
      sha256 = "78c6d7692890990a27cb1d5bbd95b7bfe47a4183ffafec5b30f689f9b58ec6f7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/r/re2/libre2-11_20240702-3+b1_amd64.deb";
      sha256 = "128136b987e90b41d1ace03348fcf42fbfb9fec8bb9294332b13eaeadfec4062";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xnnpack/libxnnpack0.20241108_0.0~git20241108.4ea82e5-2_amd64.deb";
      sha256 = "da884404596e1c64482d7063bd866f7defd7ba06bac39c4ed4c7e7b4e3ae6b4d";
      name = "libxnnpack0.20241108_0.0git20241108.4ea82e5-2_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/onnxruntime/libonnxruntime1.21_1.21.0+dfsg-1_amd64.deb";
      sha256 = "bec9de1a9358cde5752196de028c8af33d67314285143a05369860bb74b13e80";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/w/webrtc-audio-processing/libwebrtc-audio-processing-1-3_1.3-3+b1_amd64.deb";
      sha256 = "00f978b3e6318bb07f13fc21e90ca8b031866fd2fc820b777b66dbe25d4a1474";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pipewire/libspa-0.2-modules_1.6.9-2~bpo13+1_amd64.deb";
      sha256 = "d0dff90aee5ec89f0a063751177fabd8e3b7e7ab568a0dfda6b1e2927e82828b";
      name = "libspa-0.2-modules_1.6.9-2bpo13+1_amd64.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pipewire/libpipewire-0.3-0t64_1.6.9-2~bpo13+1_amd64.deb";
      sha256 = "9581bfb9843756779dfc199e48c3ec0781fbfaa3ba4685ab3b30af09ead8dac9";
      name = "libpipewire-0.3-0t64_1.6.9-2bpo13+1_amd64.deb";
    })

  ]

]
