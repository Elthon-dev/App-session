package com.elthondev.openbridge;

interface IShellCommand {
    void exec(String cmd);

    void destroy();
}