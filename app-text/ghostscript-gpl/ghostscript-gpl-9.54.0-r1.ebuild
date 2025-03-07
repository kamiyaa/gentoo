# Copyright 1999-2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit autotools toolchain-funcs

DESCRIPTION="Interpreter for the PostScript language and PDF"
HOMEPAGE="https://ghostscript.com/"

MY_PN=${PN/-gpl}
MY_P="${MY_PN}-${PV/_}"
PVM=$(ver_cut 1-2)
PVM_S=$(ver_rs 1-2 "")

MY_PATCHSET="ghostscript-gpl-9.54-patchset-01.tar.xz"

SRC_URI="https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs${PVM_S}/${MY_P}.tar.xz"

if [[ -n "${MY_PATCHSET}" ]] ; then
	SRC_URI+=" https://dev.gentoo.org/~whissi/dist/ghostscript-gpl/${MY_PATCHSET}"
fi

LICENSE="AGPL-3 CPL-1.0"
SLOT="0/$(ver_cut 1-2)"
KEYWORDS="~alpha amd64 arm ~arm64 hppa ~ia64 ~m68k ~mips ~ppc ppc64 ~riscv ~s390 sparc x86 ~amd64-linux ~x86-linux ~ppc-macos ~x64-macos ~sparc-solaris ~sparc64-solaris ~x64-solaris ~x86-solaris"
IUSE="cups dbus gtk +jpeg2k l10n_de static-libs unicode X"

LANGS="ja ko zh-CN zh-TW"
for X in ${LANGS} ; do
	IUSE="${IUSE} l10n_${X}"
done

DEPEND="
	app-text/libpaper
	media-libs/fontconfig
	>=media-libs/freetype-2.4.9:2=
	>=media-libs/jbig2dec-0.19:=
	>=media-libs/lcms-2.6:2
	>=media-libs/libpng-1.6.2:0=
	>=media-libs/tiff-4.0.1:0=
	>=sys-libs/zlib-1.2.7
	virtual/jpeg:0
	cups? ( >=net-print/cups-1.3.8 )
	dbus? ( sys-apps/dbus )
	gtk? ( || ( x11-libs/gtk+:3 x11-libs/gtk+:2 ) )
	jpeg2k? ( >=media-libs/openjpeg-2.1.0:2= )
	unicode? ( net-dns/libidn:0= )
	X? ( x11-libs/libXt x11-libs/libXext )
"
BDEPEND="virtual/pkgconfig"
RDEPEND="${DEPEND}
	app-text/poppler-data
	>=media-fonts/urw-fonts-2.4.9
	l10n_ja? ( media-fonts/kochi-substitute )
	l10n_ko? ( media-fonts/baekmuk-fonts )
	l10n_zh-CN? ( media-fonts/arphicfonts )
	l10n_zh-TW? ( media-fonts/arphicfonts )
"

S="${WORKDIR}/${MY_P}"

src_prepare() {
	if [[ -n "${MY_PATCHSET}" ]] ; then
		# apply various patches, many borrowed from Fedora
		# https://src.fedoraproject.org/rpms/ghostscript
		# and Debian
		# https://salsa.debian.org/printing-team/ghostscript/-/tree/debian/latest/debian/patches
		eapply "${WORKDIR}/patches/"*.patch
	fi

	# Upstream patches
	eapply "${FILESDIR}"/${P}-CVE-2021-3781.patch
	eapply "${FILESDIR}"/${P}-makefile-deps.patch

	default

	# remove internal copies of various libraries
	rm -r cups/libs || die
	rm -r freetype || die
	rm -r jbig2dec || die
	rm -r jpeg || die
	rm -r lcms2mt || die
	rm -r libpng || die
	rm -r tiff || die
	rm -r zlib || die
	rm -r openjpeg || die
	# remove internal CMaps (CMaps from poppler-data are used instead)
	rm -r Resource/CMap || die

	if ! use gtk ; then
		sed -e "s:\$(GSSOX)::" \
			-e "s:.*\$(GSSOX_XENAME)$::" \
			-i base/unix-dll.mak || die "sed failed"
	fi

	# Force the include dirs to a neutral location.
	sed -e "/^ZLIBDIR=/s:=.*:=${T}:" \
		-i configure.ac || die
	# Some files depend on zlib.h directly.  Redirect them. #573248
	# Also make sure to not define OPJ_STATIC to avoid linker errors due to
	# hidden symbols (https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=203327#c1)
	sed -e '/^zlib_h/s:=.*:=:' \
		-e 's|-DOPJ_STATIC ||' \
		-i base/lib.mak || die

	# search path fix
	# put LDFLAGS after BINDIR, bug #383447
	sed -e "s:\$\(gsdatadir\)/lib:@datarootdir@/ghostscript/${PV}/$(get_libdir):" \
		-e "s:exdir=.*:exdir=@datarootdir@/doc/${PF}/examples:" \
		-e "s:docdir=.*:docdir=@datarootdir@/doc/${PF}/html:" \
		-e "s:GS_DOCDIR=.*:GS_DOCDIR=@datarootdir@/doc/${PF}/html:" \
		-e 's:-L$(BINDIR):& $(LDFLAGS):g' \
		-i Makefile.in base/*.mak || die "sed failed"

	# remove incorrect symlink, bug 590384
	rm ijs/ltmain.sh || die
	eautoreconf

	cd ijs || die
	eautoreconf
}

src_configure() {
	local FONTPATH
	for path in \
		"${EPREFIX}"/usr/share/fonts/urw-fonts \
		"${EPREFIX}"/usr/share/fonts/Type1 \
		"${EPREFIX}"/usr/share/fonts \
		"${EPREFIX}"/usr/share/poppler/cMap/Adobe-CNS1 \
		"${EPREFIX}"/usr/share/poppler/cMap/Adobe-GB1 \
		"${EPREFIX}"/usr/share/poppler/cMap/Adobe-Japan1 \
		"${EPREFIX}"/usr/share/poppler/cMap/Adobe-Japan2 \
		"${EPREFIX}"/usr/share/poppler/cMap/Adobe-Korea1
	do
		FONTPATH="$FONTPATH${FONTPATH:+:}${EPREFIX}$path"
	done

	PKGCONFIG=$(type -P $(tc-getPKG_CONFIG)) \
	econf \
		--enable-dynamic \
		--enable-freetype \
		--enable-fontconfig \
		$(use_enable jpeg2k openjpeg) \
		--disable-compile-inits \
		--with-drivers=ALL \
		--with-fontpath="$FONTPATH" \
		--with-ijs \
		--with-jbig2dec \
		--with-libpaper \
		--with-system-libtiff \
		$(use_enable cups) \
		$(use_enable dbus) \
		$(use_enable gtk) \
		$(use_with cups pdftoraster) \
		$(use_with unicode libidn) \
		$(use_with X x) \
		DARWIN_LDFLAGS_SO_PREFIX="${EPREFIX}/usr/lib/"

	cd "${S}/ijs" || die
	econf \
		--enable-shared \
		$(use_enable static-libs static)
}

src_compile() {
	# Forcing j1 for both emake calls for now
	# See bug #800125
	emake -j1 so all

	cd ijs || die
	emake -j1
}

src_install() {
	emake DESTDIR="${D}" install-so install

	# move gsc to gs, bug #343447
	# gsc collides with gambit, bug #253064
	mv -f "${ED}"/usr/bin/{gsc,gs} || die

	cd "${S}/ijs" || die
	emake DESTDIR="${D}" install

	# install the CMaps from poppler-data properly, bug #409361
	dosym ../../../poppler/cMaps "/usr/share/ghostscript/${PV}/Resource/CMap"

	if ! use static-libs; then
		find "${ED}" -name '*.la' -delete || die
	fi

	if ! use l10n_de; then
		rm -r "${ED}"/usr/share/man/de || die
	fi
}
