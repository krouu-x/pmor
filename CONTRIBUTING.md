# Contributing to Streaming Starter Kit

First off, thank you for considering contributing to Streaming Starter Kit! 🎉

Contributions of all kinds are welcome, whether you're fixing bugs, improving the Roku interface, adding streaming providers, improving documentation, or suggesting new features.

This guide explains how to contribute to the project.

---

## 📋 Table of Contents

- [Getting Started](#-getting-started)
- [Project Structure](#-project-structure)
- [Development Setup](#-development-setup)
- [Areas to Contribute](#-areas-to-contribute)
- [Adding a Streaming Provider](#-adding-a-streaming-provider)
- [Coding Guidelines](#-coding-guidelines)
- [Testing Your Changes](#-testing-your-changes)
- [Reporting Bugs](#-reporting-bugs)
- [Suggesting Features](#-suggesting-features)
- [Pull Request Guidelines](#-pull-request-guidelines)
- [Commit Messages](#-commit-messages)
- [Code of Conduct](#-code-of-conduct)

---

## 🚀 Getting Started

Before contributing:

1. Make sure you have Git installed.
2. Install Node.js 18 or later.
3. Familiarize yourself with the project structure.
4. Read the main [README.md](README.md).
5. Check existing issues and pull requests to avoid duplicate work.

### Fork the Repository

1. Fork this repository on GitHub.

2. Clone your fork:

   ```bash
   git clone https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
   ```

3. Navigate into the project:

   ```bash
   cd streaming-starter-kit
   ```

4. Add the original repository as an upstream remote:

   ```bash
   git remote add upstream https://github.com/ORIGINAL_OWNER/YOUR_REPOSITORY.git
   ```

---

## 📂 Project Structure

The project contains two main components:

### Server

The Node.js backend responsible for:

- TMDB integration.
- Streaming provider management.
- API endpoints.
- Authentication and configuration.
- Stream resolution and proxying.
- Caching and provider health checks.

### RokuApp

The Roku channel application written in BrightScript.

It handles:

- User interface and navigation.
- Movie and TV show browsing.
- Communication with the server.
- Stream playback.
- Local configuration and caching.

Please keep changes isolated to the relevant component whenever possible.

---

## 🛠 Development Setup

### 1. Set Up the Server

```bash
cd Server
npm install
```

Create your environment configuration:

```bash
cp .env.example .env
```

Add your TMDB API key:

```env
TMDB_API_KEY=your_tmdb_api_key
API_PORT=8787
```

Start the development server:

```bash
npm start
```

Verify that the server is accessible:

```text
http://localhost:8787/
```

### 2. Set Up the Roku Application

You will need:

- A Roku device or Roku-compatible development environment.
- Roku Developer Mode enabled.
- Access to a running Streaming Starter Kit server.

For deployment instructions, refer to the main README.

---

## 💡 Areas to Contribute

There are several ways to improve this project.

| Area                | Possible Contributions                     |
| ------------------- | ------------------------------------------ |
| Backend             | API improvements, performance, bug fixes   |
| Streaming Providers | New providers and reliability improvements |
| Roku UI             | Navigation, layouts, animations, usability |
| Playback            | Compatibility and playback error handling  |
| Configuration       | Better settings and validation             |
| Security            | Authentication and input validation        |
| Documentation       | Guides, examples, and troubleshooting      |
| Testing             | Automated tests and bug reproduction       |

Small improvements are just as welcome as major features.

---

## 🔌 Adding a Streaming Provider

One of the most useful contributions is adding support for new streaming providers.

Providers are located in:

```text
Server/providers/
```

### General Steps

1. Create a new provider module inside `Server/providers/`.

2. Follow the existing provider module conventions.

3. Implement the expected provider interface.

4. Register the provider in:

   ```text
   Server/providers/registry.js
   ```

5. Ensure provider errors are handled gracefully.

6. Verify that the provider works with the existing API.

7. Update documentation if necessary.

### Provider Requirements

A provider should:

- Follow the existing provider interface.
- Handle missing or invalid metadata.
- Handle network failures gracefully.
- Avoid crashing the entire server.
- Return consistent response structures.
- Respect applicable content licensing and access restrictions.
- Avoid hardcoding credentials or personal configuration.

**Important:** Do not commit private cookies, API keys, session tokens, or other authentication information.

---

## 🧹 Coding Guidelines

Please follow these guidelines when submitting code.

### General

- Write readable and maintainable code.
- Use meaningful variable and function names.
- Avoid unnecessary dependencies.
- Keep functions focused on a single responsibility.
- Handle errors explicitly.
- Remove unused code and debugging statements.
- Avoid committing generated files unless required.

### Node.js Backend

- Follow the existing JavaScript conventions.
- Use asynchronous operations appropriately.
- Handle rejected promises.
- Validate external input.
- Avoid exposing sensitive information in logs.
- Keep configuration separate from application logic.

### Roku Application

- Follow existing BrightScript conventions.
- Keep UI components modular.
- Handle server communication failures.
- Avoid blocking the UI thread.
- Ensure navigation works with the Roku remote.
- Test on actual Roku hardware when possible.

---

## 🧪 Testing Your Changes

Before submitting a pull request, test your changes.

### Server Checklist

- [ ] Server starts without errors.
- [ ] Existing API endpoints still work.
- [ ] TMDB integration works.
- [ ] Provider errors are handled correctly.
- [ ] Configuration changes persist.
- [ ] Authentication still works.
- [ ] No secrets are exposed.

### RokuApp Checklist

- [ ] Application installs successfully.
- [ ] Server connection works.
- [ ] Movie browsing works.
- [ ] TV show browsing works.
- [ ] Search works.
- [ ] Navigation works with the remote.
- [ ] Playback handles unavailable streams gracefully.

### General Checklist

- [ ] No unrelated files were modified.
- [ ] No credentials or private data were committed.
- [ ] Documentation was updated where necessary.
- [ ] Changes do not introduce obvious regressions.

---

## 🐛 Reporting Bugs

Found a bug? Please open a GitHub issue.

Include as much of the following information as possible:

- **Title:** A short description of the issue.
- **Environment:** Windows, Linux, macOS, Roku model, etc.
- **Component:** Server or RokuApp.
- **Steps to reproduce:** How to trigger the problem.
- **Expected behavior:** What should happen.
- **Actual behavior:** What happens instead.
- **Logs:** Relevant error messages or server logs.

Please remove API keys, passwords, cookies, and other sensitive information before sharing logs.

---

## ✨ Suggesting Features

Feature suggestions are welcome!

When proposing a feature, explain:

1. What the feature does.
2. What problem it solves.
3. Which component it affects.
4. How it could be implemented, if you have an idea.

Check existing issues before creating a new feature request.

---

## 🔀 Pull Request Guidelines

Ready to submit your contribution?

### 1. Create a Branch

Use a descriptive branch name:

```bash
git checkout -b feature/add-new-provider
```

Other examples:

```text
fix/roku-playback-error
feature/improve-search
docs/update-installation-guide
refactor/provider-registry
```

### 2. Make Your Changes

Keep commits focused and avoid mixing unrelated changes.

### 3. Test Your Changes

Follow the testing checklist above.

### 4. Commit Your Changes

```bash
git add .
git commit -m "feat: add new streaming provider"
```

### 5. Push Your Branch

```bash
git push origin feature/add-new-provider
```

### 6. Open a Pull Request

Submit a pull request against the original repository's default branch.

Your pull request should include:

- A clear title.
- A description of what changed.
- The reason for the change.
- Testing performed.
- Screenshots or logs where relevant.
- Any related issue numbers.

Please keep pull requests focused and reasonably sized.

Maintainers may request changes before merging.

---

## 📝 Commit Messages

Use clear, descriptive commit messages.

Recommended prefixes:

| Prefix      | Purpose                 |
| ----------- | ----------------------- |
| `feat:`     | New feature             |
| `fix:`      | Bug fix                 |
| `docs:`     | Documentation changes   |
| `refactor:` | Code restructuring      |
| `perf:`     | Performance improvement |
| `test:`     | Tests                   |
| `chore:`    | Maintenance tasks       |
| `style:`    | Formatting changes      |

Examples:

```text
feat: add provider configuration support
fix: resolve Roku server connection issue
docs: improve installation instructions
refactor: simplify provider registry
perf: improve API response caching
test: add provider validation tests
```

---

## 🤝 Code of Conduct

We want this project to remain welcoming and constructive.

All contributors are expected to:

- Be respectful and professional.
- Welcome different experience levels and perspectives.
- Provide constructive feedback.
- Avoid harassment, discrimination, or personal attacks.
- Focus discussions on improving the project.

Unacceptable behavior may result in removal from project discussions or contribution privileges.

---

## 📜 License

By contributing to this repository, you agree that your contributions will be licensed under the project's existing **MIT License**, subject to its terms.

Only submit code and assets that you have the right to contribute.

---

## 🙏 Thank You!

Every contribution helps make Streaming Starter Kit better.

Whether you're fixing a tiny bug, improving the Roku interface, adding a provider, or helping someone troubleshoot an installation, your work is appreciated.

**Happy Contributing! 🍿✨**

