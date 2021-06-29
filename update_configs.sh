#!/bin/bash

set -ex

cp ../Matrix-Issues/{config,checks,language}.yml plugins/Matrix/
cp ../Coins/src/main/resources/config.yml plugins/Coins/
cp ../Essentials/Essentials/src/main/resources/config.yml plugins/Essentials/
