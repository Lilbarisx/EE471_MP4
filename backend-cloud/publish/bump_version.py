import sys
import os


def main():
    if len(sys.argv) < 2:
        print("Usage: python bump_version.py <version>")
        sys.exit(1)

    version = sys.argv[1]
    script_dir = os.path.dirname(os.path.abspath(__file__))
    version_file_path = os.path.join(script_dir, "..", "VERSION")

    with open(version_file_path, "w", encoding="utf-8") as f:
        f.write(version.strip() + "\n")

    print(f"Updated VERSION to {version}")


if __name__ == "__main__":
    main()
