"""Isolated Windows MariaDB build process; never connects to an existing service."""
import contextlib
import gzip
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import time

FLAGS = getattr(subprocess, "CREATE_NO_WINDOW", 0)


class BuildDatabase:
    def __init__(self, binaries, directory):
        self.binaries = Path(binaries)
        self.directory = Path(directory).resolve()
        self.pipe = "rikui_build_" + secrets.token_hex(12)
        self.password = secrets.token_hex(24)
        self.process = None
        self.inputs = []
        self.log = None
        self.user = "root"

    def command(self):
        return [str(self.binaries / "mariadb.exe"), "--no-defaults", "--protocol=PIPE",
                "--socket=" + self.pipe, "--user=" + self.user, "--batch", "--raw",
                "--skip-column-names", "--default-character-set=utf8mb4", "--quick",
                "--max-allowed-packet=256M", "rikui_build"]

    def query(self, sql):
        env = {**os.environ, "MYSQL_PWD": self.password}
        result = subprocess.run(self.command(), input=sql.encode("utf-8"), capture_output=True,
                                env=env, creationflags=FLAGS, timeout=300)
        if result.returncode:
            raise RuntimeError(result.stderr.decode("utf-8", "replace").replace(self.password, "[redacted]")[-2500:])
        return result.stdout.decode("utf-8")

    def start(self):
        self.directory.mkdir(parents=True, exist_ok=False)
        init = subprocess.run([str(self.binaries / "mariadb-install-db.exe"),
                               "--datadir=" + str(self.directory), "--password=" + self.password,
                               "--skip-networking", "--socket=" + self.pipe, "--silent"],
                              capture_output=True, creationflags=FLAGS, timeout=120)
        if init.returncode:
            raise RuntimeError("MariaDB initialization failed: " + init.stderr.decode("utf-8", "replace").replace(self.password, "[redacted]"))
        self.log = (self.directory / "build-server.log").open("wb")
        self.process = subprocess.Popen([str(self.binaries / "mariadbd.exe"), "--no-defaults",
            "--basedir=" + str(self.binaries.parent), "--datadir=" + str(self.directory),
            "--skip-networking", "--enable-named-pipe", "--socket=" + self.pipe,
            "--max-allowed-packet=256M", "--console"], stdout=self.log, stderr=self.log,
            creationflags=FLAGS)
        self.wait_ready()
        self.query("CREATE USER 'rikui_import'@'localhost' IDENTIFIED BY '" + self.password +
                   "'; GRANT ALL ON rikui_build.* TO 'rikui_import'@'localhost';")
        self.user = "rikui_import"
        return self

    def wait_ready(self):
        env = {**os.environ, "MYSQL_PWD": self.password}
        for _ in range(100):
            if self.process.poll() is not None:
                raise RuntimeError("Build MariaDB stopped; inspect build-server.log")
            result = subprocess.run(self.command()[:-1], input=b"CREATE DATABASE IF NOT EXISTS rikui_build;",
                                    capture_output=True, env=env, creationflags=FLAGS, timeout=5)
            if result.returncode == 0:
                return
            time.sleep(0.1)
        raise RuntimeError("Build MariaDB did not start within 10 seconds")

    def apply(self, path, root, role):
        path = Path(path)
        raw = path.read_bytes()
        data = gzip.decompress(raw) if path.suffix == ".gz" else raw
        try:
            self.query(data.decode("utf-8-sig"))
        except RuntimeError as error:
            raise RuntimeError(str(path) + ": " + str(error)) from error
        self.inputs.append({"role": role, "path": path.relative_to(root).as_posix(),
                            "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)})

    def rows(self, table):
        if not table.replace("_", "").isalnum():
            raise ValueError("Unsafe table identifier")
        columns = [line.split("\t")[0] for line in self.query("SHOW COLUMNS FROM `" + table + "`;").splitlines()]
        if any(not name.replace("_", "").isalnum() for name in columns):
            raise ValueError("Unsafe column identifier")
        fields = ",".join("'" + name + "',`" + name + "`" for name in columns)
        return [json.loads(line) for line in self.query("SELECT JSON_OBJECT(" + fields + ") FROM `" + table + "`;").splitlines()]

    def stop(self):
        if self.process and self.process.poll() is None:
            self.user = "root"
            with contextlib.suppress(Exception):
                self.query("SHUTDOWN;")
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                self.process.wait(timeout=10)
        if self.log:
            self.log.close()
