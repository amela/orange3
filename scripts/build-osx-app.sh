#!/bin/bash -e
# Build an OSX Applicaiton (.app) for Orange Canvas
#
# Example:
#
#     $ build-osx-app.sh $HOME/Applications/Orange.app
#

function print_usage() {
    echo 'build-osx-app.sh [-i] [--template] Orange.app

Build an Orange Canvas OSX application bundle (Orange.app).

NOTE: this script should be run from the source root directory.

Options:

    --template TEMPLATE_URL  Path or url to an application template as build
                             by "build-osx-app-template.sh. If not provided
                             a default one will be downloaded.
    -i --inplace             The provided target application path is already
                             a template into which Orange should be installed
                             (this flag cannot be combined with --template).
    -h --help                Print this help'
}

while [[ ${1:0:1} = "-" ]]; do
    case $1 in
        --template)
            TEMPLATE_URL=$2
            shift 2;
            ;;
        -i|--inplace)
            INPLACE=1
            shift 1
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        -*)
            echo "Unknown argument $1"
            print_usage
            exit 1
            ;;
    esac
done

# extended glob expansion / fail on filename expansion
shopt -s extglob failglob


APP=${1:-dist/Orange.app}

if [[ $INPLACE ]]; then
    if [[ $TEMPLATE_URL ]]; then
        echo "--inplace and --template can not be combined"
        print_usage
        exit 1
    fi

    if [[ -e $APP && ! -d $APP ]]; then
        echo "$APP exists and is not a directory"
        print_usage
        exit 1
    fi
fi

TEMPLATE_URL=${TEMPLATE_URL:-"http://orange.biolab.si/download/bundle-templates/Orange.app.tar.gz"}

SCHEMA_REGEX='^(https?|ftp|local)://.*'

if [[ ! $INPLACE ]]; then
    BUILD_DIR=$(mktemp -d -t orange-build)

    echo "Retrieving a template from $TEMPLATE_URL"
    # check for a url schema
    if [[ $TEMPLATE_URL =~ $SCHEMA_REGEX ]]; then
        curl --fail --silent "$TEMPLATE_URL" | tar -xf -C "$BUILD_DIR"
        TEMPLATE=( $BUILD_DIR/*.app )

    elif [[ -d $TEMPLATE_URL ]]; then
        cp -a $TEMPLATE_URL $BUILD_DIR
        TEMPLATE=$BUILD_DIR/$(basename "$TEMPLATE_URL")

    elif [[ -e $TEMPLATE_URL ]]; then
        # Assumed to be an archive
        tar -xf "$TEMPLATE_URL" -C "$BUILD_DIR"
        TEMPLATE=( $BUILD_DIR/*.app )
    else
        echo "Invalid --template $TEMPLATE_URL"
        exit 1
    fi
else
    TEMPLATE=$APP
fi
echo "Building application in $TEMPLATE"

PYTHON=$TEMPLATE/Contents/MacOS/python
PIP=$TEMPLATE/Contents/MacOS/pip

PREFIX=$("$PYTHON" -c'import sys; print(sys.prefix)')

echo "Installing bottlechest"
echo "======================"
"$PIP" install git+https://github.com/biolab/bottlechest@bottlechest#egg=bottlechest

echo "Installing orangeqt"
echo "==================="
FDIR=$TEMPLATE/Contents/Frameworks
# to find moc executable in the app bundle
EXTRA_PATH=$PREFIX/bin:$TEMPLATE/Contents/Resources/Qt4/bin
# for the compiler to find Qt's headers and frameworks
EXTRA_CXXFLAGS="-F$FDIR -I$FDIR/QtCore.framework/Headers -I$FDIR/QtGui.framework/Headers"
EXTRA_LDFLAGS="-F$FDIR -framework QtCore -framework QtGui"

(
    PATH=$EXTRA_PATH:$PATH
    CXXFLAGS=${EXTRA_CXXFLAGS}${CXXFLAGS:+:$CXXFLAGS}
    LDFLAGS=${EXTRA_LDFLAGS}:${LDFLAGS:+:$LDFLAGS}
    "$PIP" install qt-graph-helpers
)

echo "Installing Orange"
echo "================="

"$PYTHON" setup.py install

cat <<-'EOF' > "$TEMPLATE"/Contents/MacOS/Orange
	#!/bin/bash

	DIRNAME=$(dirname "$0")
	source "$DIRNAME"/ENV

	# LaunchServices passes the Carbon process identifier to the application with
	# -psn parameter - we do not want it
	if [[ $1 == -psn_* ]]; then
	    shift 1
	fi

	exec -a "$0" "$DIRNAME"/PythonAppStart -m Orange.canvas "$@"
EOF

chmod +x "$TEMPLATE"/Contents/MacOS/Orange


if [[ ! $INPLACE ]]; then
    echo "Moving the application to $APP"
    if [[ -e $APP ]]; then
        rm -rf "$APP"
    fi

    mv "$TEMPLATE" "$APP"
fi
