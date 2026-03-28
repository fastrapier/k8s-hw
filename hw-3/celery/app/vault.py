import os
import requests


class VaultClient:
    def __init__(self):
        self.addr = os.getenv("VAULT_ADDR", "http://vault.local").rstrip("/")
        self.token = os.getenv("VAULT_TOKEN", "")

        if not self.token:
            role_id = os.getenv("VAULT_ROLE_ID", "")
            secret_id = os.getenv("VAULT_SECRET_ID", "")
            if role_id and secret_id:
                self.token = self._login_approle(role_id, secret_id)
            else:
                raise RuntimeError("Set VAULT_TOKEN or (VAULT_ROLE_ID + VAULT_SECRET_ID)")

    def _login_approle(self, role_id: str, secret_id: str) -> str:
        resp = requests.post(
            f"{self.addr}/v1/auth/approle/login",
            json={"role_id": role_id, "secret_id": secret_id},
        )
        resp.raise_for_status()
        token = resp.json().get("auth", {}).get("client_token", "")
        if not token:
            raise RuntimeError("Empty client_token in AppRole response")
        return token

    def get_secret(self, path: str, key: str) -> str:
        """Read a KV-v2 secret. path like 'secret/rabbitmq', key like 'username'."""
        mount, secret_path = path.split("/", 1)
        url = f"{self.addr}/v1/{mount}/data/{secret_path}"
        resp = requests.get(url, headers={"X-Vault-Token": self.token})
        resp.raise_for_status()
        data = resp.json().get("data", {}).get("data", {})
        if key not in data:
            raise KeyError(f"Key {key!r} not found at {path}")
        return str(data[key])
