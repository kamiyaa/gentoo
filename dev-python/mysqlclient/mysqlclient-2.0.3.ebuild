# Copyright 1999-2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{8..10} )

inherit distutils-r1

DESCRIPTION="Fork of MySQL-python"
HOMEPAGE="https://pypi.org/project/mysqlclient/ https://github.com/PyMySQL/mysqlclient-python"
SRC_URI="mirror://pypi/${PN:0:1}/${PN}/${P}.tar.gz"

LICENSE="GPL-2+"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64 ~hppa ~ia64 ppc ~ppc64 ~riscv ~s390 ~sparc x86 ~amd64-linux ~x86-linux"

RDEPEND="
	dev-db/mysql-connector-c:0=
"
DEPEND="${RDEPEND}"
BDEPEND="
	test? (
		dev-db/mariadb[server]
		dev-python/mock[${PYTHON_USEDEP}]
	)
"

distutils_enable_sphinx doc
distutils_enable_tests pytest

src_test() {
	local datadir="${T}/mysql" \
		install_log="${T}/mysqld_install.log" \
		pidfile="${T}/mysqld.pid" \
		socket="${T}/mysqld.sock" \
		log="${T}/mysqld.log"
	einfo "Creating test MySQL instance ..."
	if ! mysql_install_db \
		--no-defaults \
		--auth-root-authentication-method=normal \
		--basedir="${EPREFIX}/usr" \
		--datadir="${datadir}" >& "${install_log}"
	then
		cat "${install_log}"
		die "Failed to create database"
	fi

	einfo "Starting test MySQL instance ..."
	mysqld \
		--no-defaults \
		--character-set-server=utf8 \
		--pid-file="${pidfile}" \
		--socket="${socket}" \
		--skip-networking \
		--datadir="${datadir}" >& "${log}" &

	local i timeout=10
	einfo "Waiting for MySQL to start for up to ${timeout} seconds ..."
	for i in seq 1 ${timeout}; do
		[[ -S "${socket}" ]] && break
		sleep 1
	done
	if [[ ! -S "${socket}" ]]; then
		cat "${log}"
		die "MySQL failed to start in ${timeout} seconds"
	fi

	cat > "${T}/mysql.cnf" <<- EOF
		[MySQLdb-tests]
		socket = ${socket}
		user = root
		database = test
	EOF

	distutils-r1_src_test

	einfo "Stopping test MySQL instance ..."
	pkill -F "${pidfile}" &>/dev/null
}

python_test() {
	# The C extension ("_mysql") can't be imported from "${S}/MySQLdb"
	# so we need to cd somewhere else to make sure "MySQLdb" is imported
	# from ${BUILD_DIR}/lib (thanks to PYTHONPATH).
	cd "${T}" || die
	TESTDB="${T}/mysql.cnf" epytest "${S}"
}
