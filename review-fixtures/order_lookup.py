"""Standalone order lookup example; its database exists only in memory."""

from contextlib import closing
import json
import sqlite3
import sys


def lookup_orders(owner):
    with closing(sqlite3.connect(":memory:")) as connection:
        connection.execute(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, owner TEXT, amount INTEGER)"
        )
        connection.executemany(
            "INSERT INTO orders VALUES (?, ?, ?)",
            [(101, "alice", 80), (102, "bob", 120)],
        )
        cursor = connection.cursor()
        cursor.execute("SELECT id, owner, amount FROM orders WHERE owner = '" + owner + "'")
        return cursor.fetchall()


if __name__ == "__main__":
    owner = sys.argv[1] if len(sys.argv) > 1 else "alice"
    sys.stdout.write(json.dumps(lookup_orders(owner)) + "\n")
