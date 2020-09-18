package = 'key_def'
version = 'scm-1'
source  = {
    url    = 'git://github.com/Totktonada/key_def.git',
    branch = 'master',
}
description = {
    summary  = 'key_def module for Tarantool',
    homepage = 'https://github.com/Totktonada/key_def',
    maintainer = 'Alexander Turenko <alexander.turenko@tarantool.org>',
    license  = 'BSD2',
}
dependencies = {
    'lua >= 5.1',
}
external_dependencies = {
    TARANTOOL = {
        header = 'tarantool/module.h',
    },
}
build = {
    type = 'cmake',
    variables = {
        CMAKE_BUILD_TYPE='RelWithDebInfo',
        TARANTOOL_DIR='$(TARANTOOL_DIR)',
        TARANTOOL_INSTALL_LIBDIR='$(LIBDIR)',
        TARANTOOL_INSTALL_LUADIR='$(LUADIR)',
    },
}
