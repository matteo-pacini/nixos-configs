# This is a generated file.  Do not modify!
# Following are the Debian packages constituting the closure of: libc6 libgcc-s1 libstdc++6 libasound2t64 libfontconfig1 libfreetype6 libudev1 libvulkan1 libx11-6 libxext6 libxrender1 libxrandr2 libxfixes3 libpulse0 libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 libunwind8 libgl1 libgnutls30t64 libblas3 liblapack3 libgssapi-krb5-2 libnghttp2-14 libpcsclite1 libpsl5t64 libsqlite3-0 libusb-1.0-0 libva-drm2 libva-x11-2 libva2 libvdpau1 libwayland-client0 libwayland-cursor0 libwayland-egl1

{ fetchurl }:

[

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/gcc-14-base_14.2.0-19_i386.deb";
      sha256 = "cab3cc6782d6cd3445d184ad317bbd8cc46395eb2675ccd75f4b57147469887a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libgcc-s1_14.2.0-19_i386.deb";
      sha256 = "a4c71fd856d2a48a7505a087b4186e3cca23f94603c05e3fb7c799b27e72f761";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/glibc/libc6_2.41-12+deb13u4_i386.deb";
      sha256 = "67bb4b54cf4bb6a380449dfa1852cd9135659f85360caa0e41d312f4b30e573a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libstdc++6_14.2.0-19_i386.deb";
      sha256 = "b6020260b92a97ac33ae58a73b16f3ab31fed7632e9b861f7cd5fc393facd6ed";
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
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/a/alsa-lib/libasound2t64_1.2.16.1-1~bpo13+1_i386.deb";
      sha256 = "24259a0916c3793a8f0dae3469bbb82076c2bfca41e5a985a59f084fb1aca839";
      name = "libasound2t64_1.2.16.1-1bpo13+1_i386.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/e/expat/libexpat1_2.8.3-1~deb13u1_i386.deb";
      sha256 = "d0396d41674a2fb1946af2b131630534a2cf09d160c8ea13bc5bbaa7416f071a";
      name = "libexpat1_2.8.3-1deb13u1_i386.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/brotli/libbrotli1_1.1.0-2+b7_i386.deb";
      sha256 = "696b5206497da474e9480c0a4700d0835ee34f90ee0e505091a9402e70fc1a71";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/b/bzip2/libbz2-1.0_1.0.8-6_i386.deb";
      sha256 = "c23dee450dcee574135cbe004d463be3f413cdc017b22d8273c5ce0a18a7de10";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/z/zlib/zlib1g_1.3.dfsg+really1.3.1-1+b1_i386.deb";
      sha256 = "8950c79b1ade51f53b2f37863aec532cfaca3dff315e28f0c5b53902425c41ed";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libp/libpng1.6/libpng16-16t64_1.6.48-1+deb13u5_i386.deb";
      sha256 = "907c103a7d17b2b39661f93a9f4e439cf5fb4ac1ee03c9d3cd2243d3f82e8970";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/freetype/libfreetype6_2.13.3+dfsg-1+deb13u1_i386.deb";
      sha256 = "fbe01c5a6e2654ed7c8fbb08b39c9b20cf19bd24554088d11762c330f7af1dd2";
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
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/fontconfig/fontconfig-config_2.15.0-2.3_i386.deb";
      sha256 = "03d0f0fb481a4cb7889ba364ec77a24e0a2c0c987b2a1833f5ea0a9a7d6b23af";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/fontconfig/libfontconfig1_2.15.0-2.3_i386.deb";
      sha256 = "d24faaee293c8f76fd68dea181ac927ad8fb8ec18fcdf7e5bf6fe847678f227b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libc/libcap2/libcap2_2.75-10+deb13u1+b3_i386.deb";
      sha256 = "15cdfa6ca972c7c81e48e0c030a2b3ae16acb146cca45659bf72919f4af94aeb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/systemd/libudev1_257.13-1~deb13u1_i386.deb";
      sha256 = "ba085b6e9587a9e5f5aec062ae493b35901ee0e07aebe3aec4261c85e87812f6";
      name = "libudev1_257.13-1deb13u1_i386.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/v/vulkan-loader/libvulkan1_1.4.309.0-1_i386.deb";
      sha256 = "5561b8b95bfd4123dc6f7c73e332591840d3e116e5d067e9e813843a630e1230";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxau/libxau6_1.0.11-1_i386.deb";
      sha256 = "1645415b2ea8b64268f87944b733b9f9a2f243f89eb73555120eaf459fa06a57";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxdmcp/libxdmcp6_1.1.5-1_i386.deb";
      sha256 = "06b3a5d82fd69b1ff66e4e68fd4cf55f616864a29f456609a1f92b275b6126f7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb1_1.17.0-2+b1_i386.deb";
      sha256 = "a4c421cf27ef4f66b32f650e3ac8bbd12bc8ec28b70a3be5dcc56dc3453e8d3e";
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
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libx11/libx11-6_1.8.12-1_i386.deb";
      sha256 = "0a4ee67fffb3299953a9bd298c33e4f66d1b7f2f112eb83eb32c8e4351927741";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxext/libxext6_1.3.4-1+b3_i386.deb";
      sha256 = "9e15d0b7f325c70081acb33e21bf019a1bb7c9f0df262ece49bef91d072705a1";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxrender/libxrender1_0.9.12-1_i386.deb";
      sha256 = "c1666fddcb0ded151fbe3a2569264761b4e8a18e862bcc2bce156aa0f06d3473";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxrandr/libxrandr2_1.5.4-1+b3_i386.deb";
      sha256 = "b3940d28cd51c5fb295737085bcca24064f3288a3b98cea3f9f92a4dfa757c72";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxfixes/libxfixes3_6.0.0-2+b4_i386.deb";
      sha256 = "5ab7a33e21647a5398d422eff7426595c1bcbb8a58574c0cc8aa1a4f0a44c6cc";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/liba/libasyncns/libasyncns0_0.8-6+b5_i386.deb";
      sha256 = "57528d6cb22dbc007ba432a8a3294144fc88144eb49c645cb3a8e671e357f412";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/systemd/libsystemd0_257.13-1~deb13u1_i386.deb";
      sha256 = "e034259827e162c4c01ef4412bc6a2c4b4c3e2744767e5c08338132a0e2cf0ad";
      name = "libsystemd0_257.13-1deb13u1_i386.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/d/dbus/libdbus-1-3_1.16.2-2_i386.deb";
      sha256 = "2a6491a71245ea6863b5873743ee3f57b89dc9b3698441a94704b9360050652e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libo/libogg/libogg0_1.3.5-3+b2_i386.deb";
      sha256 = "4ee76bfbd7c9408571a0dbe2b21223d4bac7598e93c2d5082f2752a59332ebbc";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/f/flac/libflac14_1.5.0+ds-2_i386.deb";
      sha256 = "a83bfb785cf7dd1c99d22f3e1f62d6faba5a982bf13461bf31bced4c2305aba5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/lame/libmp3lame0_3.100-6+b3_i386.deb";
      sha256 = "df68cd18e2f747fe2d93f740b2d0df206da80adac9fff2a2346faa5690a66fc3";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mpg123/libmpg123-0t64_1.32.10-1+deb13u1_i386.deb";
      sha256 = "4080376b9d3e730f5020552223507e1c93696ab1d7ba56da2afccf97978c7238";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/opus/libopus0_1.5.2-2_i386.deb";
      sha256 = "eac2162ec314a46d5b93f1d7943368cc7704ec627629c342361fb8101cc67dbb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libv/libvorbis/libvorbis0a_1.3.7-3_i386.deb";
      sha256 = "32b6df776b5504097392c04045728e8920f28fee73a0748845e89852c6d372c5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libv/libvorbis/libvorbisenc2_1.3.7-3_i386.deb";
      sha256 = "d15bd9a2f93f0742ddf53b2a7cf25038cc2a52ff532327af47eaa77a366010be";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libs/libsndfile/libsndfile1_1.2.2-2+deb13u1_i386.deb";
      sha256 = "004654d5a78eb710586807322f41144e54c8c88ea3347f007c4b6b0d59b37d21";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libx11/libx11-xcb1_1.8.12-1_i386.deb";
      sha256 = "c17ba14a5a1c8b5733eef8eb54e640df27816d5fa6636c512d75374ca5305029";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pulseaudio/libpulse0_17.0+dfsg1-2+b1_i386.deb";
      sha256 = "ec7887ebe910ea46f6c0fd9f813e1338608361ce6d50582d7e2474fd753d582e";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libatomic1_14.2.0-19_i386.deb";
      sha256 = "99b97383f7b8c768e04b5bed83b3854c5a4d9eaed2558632508fde8ef2ec7906";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libf/libffi/libffi8_3.4.8-2_i386.deb";
      sha256 = "8bafefb38c320ca27796070c881595ce04d900c3b534ac142a494daf1fe1db13";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/u/util-linux/libblkid1_2.41.5-0+deb13u1_i386.deb";
      sha256 = "541f172e77a6e8148ae0171f7dabd11545cf3dc4a3b53e4d1782c9538a388f9a";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pcre2/libpcre2-8-0_10.46-1~deb13u2_i386.deb";
      sha256 = "d73a12ec13f4bbd963ac737ee14773a2f89d4289b25c125e6642b0e3b159ed2e";
      name = "libpcre2-8-0_10.46-1deb13u2_i386.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libs/libselinux/libselinux1_3.8.1-1_i386.deb";
      sha256 = "9d5628efff228a00a804638409e3c265ada5cf5ccc6eb25cf37865179c945f74";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/u/util-linux/libmount1_2.41.5-0+deb13u1_i386.deb";
      sha256 = "d93e3014d2af147b4a5e6324ce28dd83f12d0375c7398c6d5f9e185eb6304577";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/glib2.0/libglib2.0-0t64_2.84.4-3~deb13u5_i386.deb";
      sha256 = "e773e9c94f3c833ffa75fe8531cb16c8e9f4717cc76201badffeb45c1b4bf56c";
      name = "libglib2.0-0t64_2.84.4-3deb13u5_i386.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libc/libcap2/libcap2-bin_2.75-10+deb13u1+b3_i386.deb";
      sha256 = "ee657bc443a68f460622355bde50d072f9e8eb3b56151feead6b5b098ccb3ec8";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gstreamer1.0/libgstreamer1.0-0_1.26.2-2_i386.deb";
      sha256 = "2714573c8b6ee49647520d10b284920a44d97e39b68056f8941edf95fdbac2d8";
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
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libd/libdrm/libdrm2_2.4.124-2_i386.deb";
      sha256 = "366cf26a5c5f1003225ef57b442b3dce8a5dd555487633bd2de5278edca9e854";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/orc/liborc-0.4-0t64_0.4.41-1_i386.deb";
      sha256 = "91049ec109c531717e1b855caf10fb07d7d176145d7ad05b8b6ee96ea12094ed";
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
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gst-plugins-base1.0/libgstreamer-plugins-base1.0-0_1.26.2-1+deb13u1_i386.deb";
      sha256 = "3e061039cc3a390d9b5dabac8d5184bcaaafce36ed22baa06d2218366639f485";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/x/xz-utils/liblzma5_5.8.1-1+deb13u1_i386.deb";
      sha256 = "d686140b257bdc58e342a22ab5006c9d0327553a3ac273838109ef9ddf55621c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libu/libunwind/libunwind8_1.8.1-0.1_i386.deb";
      sha256 = "10ee757b9613f468a6bf04462deccd9e41be80ca9c0747dac89b8063e61fa0e7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libg/libglvnd/libglvnd0_1.7.0-1+b2_i386.deb";
      sha256 = "756fce6f41fae7c61ce16cdb80815083833f78e382819b93d2b65d63f6dd71a0";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libd/libdrm/libdrm-amdgpu1_2.4.124-2_i386.deb";
      sha256 = "e4f8efca9d0214ffe890165ed87a8a5675ace48713a4d53f979df68c32ae4ccb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libp/libpciaccess/libpciaccess0_0.17-3+b3_i386.deb";
      sha256 = "d16fddaa98f1f1016b70ea6bb15e24e5fc2a837c8c1107e0c6e02cdbf8d3c999";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libd/libdrm/libdrm-intel1_2.4.124-2_i386.deb";
      sha256 = "a7e30963f22af48d68d78f6400ea43d25d5452d108f651886ebe962504ce3469";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libz/libzstd/libzstd1_1.5.7+dfsg-1_i386.deb";
      sha256 = "305f0ab5f16552c44906b3f3f6e9ad3eb33f6f857c3347fdf3bd987abd6989a9";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/e/elfutils/libelf1t64_0.196-1~bpo13+2_i386.deb";
      sha256 = "353fd38cf9cb979837d327224e9cce0959dd2ad4845cc49b11bbf9b7f7112ae3";
      name = "libelf1t64_0.196-1bpo13+2_i386.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libm/libmd/libmd0_1.1.0-2+b1_i386.deb";
      sha256 = "42e150e95df064f5e9704cca46fc6d5755416681c96811cfa468e5a638dd425d";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libb/libbsd/libbsd0_0.12.2-2_i386.deb";
      sha256 = "72dccfe87335f7c5efde97345b3ddf3157fdc5b0c441a8cb413722928ddcd510";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/ncurses/libtinfo6_6.5+20250216-2_i386.deb";
      sha256 = "3488ab080c07056b2ddef81f3d75fac7358ebfd63ac04a224fa87571152f39b7";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libe/libedit/libedit2_3.1-20250104-1_i386.deb";
      sha256 = "484df5a0249534e8a1378733f33058a616ff4b9d3349c7830d1b14548e9759c3";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxml2/libxml2_2.12.7+dfsg+really2.9.14-2.1+deb13u3_i386.deb";
      sha256 = "361ae44454c7bbdb0a01a3564a9838a0fc5d32b563e4a7f03bcae8d4b484588b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/z/z3/libz3-4_4.13.3-1_i386.deb";
      sha256 = "9d2e21a41837b7d3dbb97cebf38a7f14b5d4dc1e12a14c0cc3a10c99b198b66d";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/llvm-toolchain-19/libllvm19_19.1.7-3+b1_i386.deb";
      sha256 = "a285dd9bf5f9552084a68886ce1ac1cc83913cc9b68dfb58504e17c06d0f9846";
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
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/lm-sensors/libsensors5_3.6.2-2_i386.deb";
      sha256 = "b999b735f40d17cc274f80fe98194e1a1edfd134de772168d34acd19ce587ca2";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-dri3-0_1.17.0-2+b1_i386.deb";
      sha256 = "8ec62578b10cdf0b85e5298563ac16fe69bfdc1c1a87c5be35140343f3dc8927";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-present0_1.17.0-2+b1_i386.deb";
      sha256 = "d3453767790b2ef25a546e3c3ecd4545945a588c9dd95221fd0ecd9fded054f1";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-randr0_1.17.0-2+b1_i386.deb";
      sha256 = "e31b2b6b7d0937a4052f143ccd4c639c2afae28a22c32a6c083d07c5bce025a9";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-sync1_1.17.0-2+b1_i386.deb";
      sha256 = "5d18a7856f73baaa192d51ef6e8b3f03b4268837c9769a508a04067274446aff";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-xfixes0_1.17.0-2+b1_i386.deb";
      sha256 = "b715b1a5d5f41632b5c5592f1c413401cf1538d9788f8e8ab91448522f26b123";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxshmfence/libxshmfence1_1.3.3-1_i386.deb";
      sha256 = "4ec808885b3d94846ed2fa7039b1388e21828ed083630b50f74a338c2075654b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mesa/mesa-libgallium_26.1.6-1~bpo13+1_i386.deb";
      sha256 = "5e609f310e4a7903a2747565587af5a7b013f1bc3c791cfbecd55fb518d22d54";
      name = "mesa-libgallium_26.1.6-1bpo13+1_i386.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mesa/libgbm1_26.1.6-1~bpo13+1_i386.deb";
      sha256 = "14798a3f68cddccf2425aadeef0165a0ff4e34497082e4c9e900e55bfa51f794";
      name = "libgbm1_26.1.6-1bpo13+1_i386.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mesa/libgl1-mesa-dri_26.1.6-1~bpo13+1_i386.deb";
      sha256 = "375c538df22e86bc2b6206af7be608b557e72dfc854d2fb58740affa4016ac91";
      name = "libgl1-mesa-dri_26.1.6-1bpo13+1_i386.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-glx0_1.17.0-2+b1_i386.deb";
      sha256 = "eec799cf9a756f8b8ec5357d21ae973e526ce2ccce8be2e141695f7337df0902";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxcb/libxcb-shm0_1.17.0-2+b1_i386.deb";
      sha256 = "c96eb689f88d25e284328eff50f2faf334c13648ef5ea66fe7e1a3ef5849b0b5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libx/libxxf86vm/libxxf86vm1_1.1.4-1+b4_i386.deb";
      sha256 = "b3f612262c335fde6536d4fa62df37640a5e376c29e8e484bfce70f7ee6eabd0";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/m/mesa/libglx-mesa0_26.1.6-1~bpo13+1_i386.deb";
      sha256 = "464d70f4bd3a55be7c4a3a0341857a263c101c0df87c8496c11443a10af9a2b4";
      name = "libglx-mesa0_26.1.6-1bpo13+1_i386.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libg/libglvnd/libglx0_1.7.0-1+b2_i386.deb";
      sha256 = "94b2d3e10d5fa4aac9fd98bbdff7d7285f70051276225b67ac8017d0516d5830";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libg/libglvnd/libgl1_1.7.0-1+b2_i386.deb";
      sha256 = "2d61aa7c7b39a07e3bc691239b524fee99a2fc92da2b6706b518db7b0e315554";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gmp/libgmp10_6.3.0+dfsg-3_i386.deb";
      sha256 = "f005fef33ce70d6775070c60017f0d29a0c415f1b657b4cc622d1a556561615c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/nettle/libnettle8t64_3.10.1-1_i386.deb";
      sha256 = "6daa71300749e0ec1e0792dc4b1886ffae6668317d363aa13c2f30f3b8d96792";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/nettle/libhogweed6t64_3.10.1-1_i386.deb";
      sha256 = "c947e90d9451239ebfa85f67ae0a6c3f9dc19b8bd9f0bb7c98a73dff33665592";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libu/libunistring/libunistring5_1.3-2_i386.deb";
      sha256 = "d7f66009fe785d4964ca749ddf38602d692e944847dfdef1ccf76b4d30e050b2";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libi/libidn2/libidn2-0_2.3.8-2_i386.deb";
      sha256 = "385d7ec787a45c8afbca118f30c770186004542011699ae0b51b37ed5f9a5b22";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/p11-kit/libp11-kit0_0.25.5-3_i386.deb";
      sha256 = "87454329e53dab3176c2f61f50386ac2c42d6088a68fb882b3804f8bc0ba7660";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libt/libtasn1-6/libtasn1-6_4.20.0-2+deb13u1_i386.deb";
      sha256 = "e12a0eb8430e54eacdc4e650c93fb5c5db66594e0a3f5885127a3ab3ed275981";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gnutls28/libgnutls30t64_3.8.9-3+deb13u4_i386.deb";
      sha256 = "8cf569d66f972184d90bdb424eb5b0af1245df4abb15f229d30b6c905d565265";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/lapack/libblas3_3.12.1-6_i386.deb";
      sha256 = "91fb227a2f70900d48a030ea3ecf73cc9649cfc8548fd4c7b8459ff037d3682f";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/g/gcc-14/libgfortran5_14.2.0-19_i386.deb";
      sha256 = "256f5da47a804ed9d0f9d00f9e89b8fbee1a04c19fce016db78780bfc08204ea";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/l/lapack/liblapack3_3.12.1-6_i386.deb";
      sha256 = "744721658fce4da5aea4af3422ec596064c016a989d5b418a30d0fec2bb192ea";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/k/krb5/libkrb5support0_1.21.3-5+deb13u1_i386.deb";
      sha256 = "d48c9a178c6d123f30cb8721913553a755ceb8d0b30e280115aa14c35e300772";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/e/e2fsprogs/libcom-err2_1.47.2-3+b12_i386.deb";
      sha256 = "0a1ed6fc09b01df4a567b66aa9c84b190f9da2e1c0d1df70b3cd8b4865743fc5";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/k/krb5/libk5crypto3_1.21.3-5+deb13u1_i386.deb";
      sha256 = "2b7baf4667e5e090eadf8bb039973ab553989b464d1dba04c0c2b2c78d988c1c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/k/keyutils/libkeyutils1_1.6.3-6_i386.deb";
      sha256 = "ee25840a728d2cca5c3d7efe0db9f4c26ef1df88fc2265705164fb4db0576f0c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/openssl/openssl-provider-legacy_3.5.7-1~deb13u2_i386.deb";
      sha256 = "8ec8d6aa3b4a7307601d973d3c11a75026a2a953367f6b12a68e389ec7a49ee2";
      name = "openssl-provider-legacy_3.5.7-1deb13u2_i386.deb";
    })

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/o/openssl/libssl3t64_3.5.7-1~deb13u2_i386.deb";
      sha256 = "30cd19b3f34b9d688d3a373082ccc8907bff1e52efb7f344266eceed100bcd18";
      name = "libssl3t64_3.5.7-1deb13u2_i386.deb";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/k/krb5/libkrb5-3_1.21.3-5+deb13u1_i386.deb";
      sha256 = "baae87f24ca36525bd20ae079d5de349ab2df1cce066e4c952cfd50934f6e179";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/k/krb5/libgssapi-krb5-2_1.21.3-5+deb13u1_i386.deb";
      sha256 = "d211e7815c8c7343936ad32920fab5eb476b606d868451f978fc995e305751db";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/n/nghttp2/libnghttp2-14_1.64.0-1.1+deb13u1_i386.deb";
      sha256 = "18ce615b00c11b21bddf2e008e7651d760a01c18c65fd87acd5ee3b8e4b442cf";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/p/pcsc-lite/libpcsclite1_2.3.3-1_i386.deb";
      sha256 = "71e98b997e91c2534e5f613a1cddbad7d92f757e9edee76d27dd6673a4a45487";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libp/libpsl/libpsl5t64_0.21.2-1.1+b1_i386.deb";
      sha256 = "9249ffed697cf6c0d47de46802e97b146e84048e0e01773201d932ea2f245f3b";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/s/sqlite3/libsqlite3-0_3.46.1-7+deb13u2_i386.deb";
      sha256 = "1071476dbe1efb0aef16bbaed98de853fe82c496cd22e75ce9e1545f1e163209";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libu/libusb-1.0/libusb-1.0-0_1.0.28-1_i386.deb";
      sha256 = "318d7d5649d518cfff4f27e5428f8462fc37cee03d2780e6f435fbcb9d20661c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libv/libva/libva2_2.22.0-3_i386.deb";
      sha256 = "d79110da58668e93b6728d51130db75cc0010f4fbd9a73daf43a0cdd4be3deff";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libv/libva/libva-drm2_2.22.0-3_i386.deb";
      sha256 = "ac3d78a88be35f242ca9cd490b5272250401e99e0f501255f0a981e533c26247";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libv/libva/libva-x11-2_2.22.0-3_i386.deb";
      sha256 = "ed03673aac6d305bf766287c385b346e4c97b9c45ce78abf8e2b4ab57092802c";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/libv/libvdpau/libvdpau1_1.5-3+b1_i386.deb";
      sha256 = "13f36dd66c5c9cbce02855cbebda3ad4845601257692a703d727248499d35480";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/w/wayland/libwayland-client0_1.23.1-3_i386.deb";
      sha256 = "90b8eead79f4d4b11497752e58a848a3684e4a922b14bdd6445aab1f17573461";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/w/wayland/libwayland-cursor0_1.23.1-3_i386.deb";
      sha256 = "3bbcfde3f8a862578e241e69800e9c17e2dbbe2a160184f8b8d1a1170f9341da";
    })

  ]

  [

    (fetchurl {
      url = "https://snapshot.debian.org/archive/debian/20261006T082722Z/pool/main/w/wayland/libwayland-egl1_1.23.1-3_i386.deb";
      sha256 = "055ad770511071a20a7ae4f9e34bbdc48ff1bf4382343cf330bc8f64da4e0a6e";
    })

  ]

]
