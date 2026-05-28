# Python sample fixture for ASTChunker tests

from typing import List, Optional
import os


class Repository:
    """Represents a git repository."""

    def __init__(self, name: str, url: str, branch: str = "main"):
        self.name = name
        self.url = url
        self.branch = branch

    def __repr__(self) -> str:
        return f"Repository(name={self.name!r}, branch={self.branch!r})"


def clone_repository(repo: Repository, work_dir: str) -> bool:
    """Clone a repository to the given work directory.

    Returns True on success, False on failure.
    """
    target = os.path.join(work_dir, repo.name)
    if os.path.exists(target):
        return False
    print(f"Cloning {repo.name} from {repo.url}")
    return True


class GitClient:
    """High-level git client managing multiple repositories."""

    def __init__(self, work_dir: str):
        self.work_dir = work_dir
        self._repositories: List[Repository] = []

    def add_repository(self, repo: Repository) -> None:
        self._repositories.append(repo)

    def fetch_all(self) -> List[bool]:
        results = []
        for repo in self._repositories:
            result = clone_repository(repo, self.work_dir)
            results.append(result)
        return results

    def get_repositories(self) -> List[Repository]:
        return list(self._repositories)

    def find_by_name(self, name: str) -> Optional[Repository]:
        for repo in self._repositories:
            if repo.name == name:
                return repo
        return None
