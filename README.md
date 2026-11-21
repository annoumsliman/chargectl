chargectl
=========

A small shell script to control the battery charge thresholds of a Linux
laptop (Ubuntu and derivatives) from the terminal. It writes to the kernel's
standard sysfs files, so it needs no daemon of its own and no extra
dependency.

    sudo chargectl 75 80              # start charging below 75%, stop at 80%
    sudo chargectl 75 80 --persist    # same, and apply it again at every boot
    sudo chargectl disable            # stop charging, even when plugged in
    sudo chargectl enable             # allow charging again
    chargectl status                  # show thresholds, state and saved values
    sudo chargectl forget             # delete the saved boot thresholds


Requirements
------------

Your laptop and kernel must expose the charge limit. Check:

    ls /sys/class/power_supply/BAT*/charge_control_*_threshold

If both files are listed, the thresholds work. If you get "No such file or
directory", this tool cannot help on your machine.

`enable` and `disable` need a second file:

    cat /sys/class/power_supply/BAT0/charge_behaviour

It should print something like `[auto] inhibit-charge force-discharge`. If the
file does not exist, only the thresholds are available.


Install
-------

Keep `chargectl` and `install.sh` in the same directory, then:

    sudo bash install.sh

This installs the script and enables a boot service. Nothing else to set up:
use `--persist` whenever you want your thresholds to survive reboots.

What the installer does and does not do:

- It installs `chargectl` to /usr/local/bin and the service
  /etc/systemd/system/chargectl.service. Nothing else.
- The service contains no numbers. At boot it runs `chargectl restore`,
  which applies the thresholds saved with `--persist`, or does nothing if
  none are saved.
- It refuses to run if your battery does not support charge limits.
- It never overwrites a file it did not install. With `--force` it makes a
  backup first (/usr/local/bin/chargectl.bak.DATE).
- It only touches a service file that carries its own marker line.
- If it finds a boot service from an older version of this installer, it
  keeps the thresholds that service used.
- It warns if TLP is active, or if an older battery-limit.service exists.

You can run the installer again at any time to update the script.


Usage
-----

    chargectl START STOP [--persist]
    chargectl enable|disable
    chargectl status
    chargectl forget
    chargectl --help

START and STOP are integers from 0 to 100, with START lower than STOP.
START is the level below which charging resumes; STOP is the level at which
charging stops. Between the two, the battery does not charge, which avoids
constant top-ups while plugged in.

Setting values, enable, disable and forget need root. `status` does not.

`on` and `off` are accepted as aliases of `enable` and `disable`.

Another battery: the first battery that has a charge limit is used. To pick
one yourself:

    sudo CHARGECTL_BATTERY=BAT1 chargectl 75 80


Persistence
-----------

The kernel forgets the thresholds at every reboot. With `--persist`,
chargectl also saves the two numbers in /etc/chargectl.conf, and the boot
service applies them again at every boot:

    sudo chargectl 60 80 --persist

Without `--persist`, the values last until the next reboot. This is handy
for a one-time full charge before a trip:

    sudo chargectl 0 100

After the next reboot, your saved thresholds are back.

`status` shows the saved values on the line "Saved for boot".

To stop applying saved values at boot:

    sudo chargectl forget

Check that the service is enabled:

    systemctl is-enabled chargectl.service

`disable` and `enable` are never saved: after a reboot, charging is always
back to normal.


Uninstall
---------

    sudo bash install.sh --uninstall

This removes the script, the service and /etc/chargectl.conf, then puts the
battery back to normal (charging enabled, thresholds 0 and 100, where
supported).


How it works
------------

The script writes to:

    /sys/class/power_supply/BATx/charge_control_start_threshold
    /sys/class/power_supply/BATx/charge_control_end_threshold
    /sys/class/power_supply/BATx/charge_behaviour

The kernel requires START to stay lower than STOP at every step, so the
script writes STOP first when raising the limit and START first when
lowering it. That avoids the "Invalid argument" error.

The older names `charge_start_threshold` and `charge_stop_threshold` are
aliases on most drivers and are not used.


Troubleshooting
---------------

"Permission denied": run the command with sudo.

"No such file or directory": the battery does not expose charge limits, or the
name is not BAT0. See Requirements.

"Invalid argument": the driver rejected the value. Some laptops only accept
certain values, for example 60 or 80 as STOP, or START at least 2 points below
STOP. Try other numbers.

"chargectl.service is not enabled": the values were saved but nothing applies
them at boot. Run `sudo bash install.sh` again.

Thresholds are back to 0 and 100 after a reboot: you did not use `--persist`,
or another tool reset them. If TLP is installed, it may overwrite your values;
remove it or configure the thresholds in /etc/tlp.conf instead.

The GNOME power profile toggle is missing: unrelated to this tool. TLP and
power-profiles-daemon conflict; see `powerprofilesctl list`.


Safety
------

Low limits (for example 10) keep the laptop almost uncharged and can power it
off unplugged. Choose a range such as 60 to 80 for daily use. Changing the
thresholds does not damage the hardware, and you can always restore the
defaults with:

    sudo chargectl 0 100
    sudo chargectl enable
    sudo chargectl forget
