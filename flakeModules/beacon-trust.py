import argparse
import pathlib
import subprocess
import sys
import tempfile


class BeaconTrustError(Exception):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Trust the scanned beacon SSH host key.",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="trust the scanned beacon host key without prompting",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="replace an existing beacon known_hosts file if it differs",
    )
    for name in ("--beacon-ip", "--beacon-port", "--beacon-host-alias"):
        parser.add_argument(name, required=True, help=argparse.SUPPRESS)
    parser.add_argument(
        "--beacon-known-hosts",
        required=True,
        type=pathlib.Path,
        help=argparse.SUPPRESS,
    )
    return parser.parse_args()


def trust_beacon(args: argparse.Namespace) -> None:
    destination = args.beacon_known_hosts
    target = f"{args.beacon_ip}:{args.beacon_port}"

    keyscan = subprocess.run(
        [
            "ssh-keyscan",
            "-T",
            "10",
            "-p",
            args.beacon_port,
            args.beacon_ip,
        ],
        text=True,
        capture_output=True,
    )
    if keyscan.returncode != 0:
        raise BeaconTrustError(
            f"Failed to scan beacon SSH host key at {target}"
        )

    lines: list[str] = []
    for line in keyscan.stdout.splitlines():
        if not line or line.startswith("#"):
            continue

        fields = line.split()
        if len(fields) != 3:
            raise BeaconTrustError(
                f"Unexpected ssh-keyscan output line: {line}"
            )

        lines.append(f"{args.beacon_host_alias} {fields[1]} {fields[2]}")
    if not lines:
        raise BeaconTrustError(f"No beacon SSH host key found at {target}")

    content = ("\n".join(lines) + "\n").encode()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        dir=destination.parent,
        prefix=f"{destination.name}.tmp.",
    ) as tmp_dir:
        tmp_path = pathlib.Path(tmp_dir) / destination.name
        tmp_path.write_bytes(content)
        fingerprints = subprocess.run(
            ["ssh-keygen", "-l", "-f", str(tmp_path)],
            text=True,
            capture_output=True,
        )
        if fingerprints.returncode != 0:
            sys.stderr.write(fingerprints.stderr)
            raise BeaconTrustError(
                "Failed to print beacon SSH host key fingerprints"
            )

        print("Scanned beacon SSH host key fingerprints:", file=sys.stderr)
        sys.stderr.write(fingerprints.stdout)

        if (
            destination.exists()
            and destination.read_bytes() != content
            and not args.force
        ):
            raise BeaconTrustError(
                f"Beacon host key differs from {destination}.\n"
                "Verify the new fingerprint, then rerun with "
                "--force to replace it."
            )

        if not args.yes:
            print(
                "Trust this beacon host key? [y/N]: ",
                end="",
                file=sys.stderr,
                flush=True,
            )
            answer = sys.stdin.readline().strip().lower()
            if answer not in {"y", "yes"}:
                raise BeaconTrustError("Aborting.")

        tmp_path.replace(destination)
        print(
            f"Wrote {destination} for {args.beacon_host_alias}.",
            file=sys.stderr,
        )


def main() -> int:
    try:
        trust_beacon(parse_args())
    except BeaconTrustError as err:
        print(err, file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
