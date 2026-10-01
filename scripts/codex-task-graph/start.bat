@echo off
title Codex Task Graph
pushd "%~dp0"
node server\index.js --open
popd
