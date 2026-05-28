// TypeScript sample fixture for ASTChunker tests

interface Repository {
    name: string;
    url: string;
    branch: string;
}

function cloneRepository(repo: Repository): Promise<void> {
    return new Promise((resolve, reject) => {
        console.log(`Cloning ${repo.name} from ${repo.url}`);
        resolve();
    });
}

class GitClient {
    private repositories: Repository[] = [];

    constructor(private workDir: string) {}

    addRepository(repo: Repository): void {
        this.repositories.push(repo);
    }

    async fetchAll(): Promise<void> {
        for (const repo of this.repositories) {
            await cloneRepository(repo);
        }
    }

    getRepositories(): Repository[] {
        return [...this.repositories];
    }
}

export { GitClient, Repository, cloneRepository };
