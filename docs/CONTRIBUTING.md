# **__CONTRIBUTING TO XRPL MONITOR__**

*Guidelines and best practices for contributing to XRPL Monitor development.*

---

# Table of Contents

- [Development Best Practices](#development-best-practices)
- [Development Workflow](#development-workflow)
- [Code Style and Standards](#code-style-and-standards)
- [Testing](#testing)
- [Documentation](#documentation)
- [Pull Request Process](#pull-request-process)
- [Grafana Dashboard Development](#grafana-dashboard-development)
- [Troubleshooting](#troubleshooting)
- [Getting Help](#getting-help)
- [Code of Conduct](#code-of-conduct)
- [License](#license)

---

# Development Best Practices

### 1. Commit Before Starting New Work

**IMPORTANT:** Always commit and push your changes to GitHub before starting new work.

This practice ensures:
- Clean separation of features/fixes
- Easy rollback if something goes wrong
- Clear git history
- No mixing of unrelated changes

**Workflow:**
```bash
# 1. Check what's changed
git status
git diff --stat

# 2. Stage relevant changes (skip debug/test files)
git add <files>

# 3. Create descriptive commit
git commit -m "feat: description of changes

Detailed explanation of what changed and why."

# 4. Push to GitHub
git push origin main

# 5. NOW start new work
```

**Example:**
```bash
# Before starting Phase 1 of Grafana enhancements
git add src/ docs/ dashboards/
git commit -m "feat: Implement HTTP admin API for peers command"
git push origin main

# Now safe to start Phase 1 work
```

---

# Development Workflow

### Setting Up Development Environment

1. **Clone the repository:**
   ```bash
   git clone https://github.com/realgrapedrop/xrpl-validator-dashboard.git
   cd xrpl-validator-dashboard
   ```

2. **Create Python virtual environment:**
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # Linux/Mac
   # or
   .\venv\Scripts\activate   # Windows
   ```

3. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

4. **Copy environment file:**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

5. **Start services:**
   ```bash
   docker-compose up -d
   ```

---

# Code Style and Standards

**In This Section:**
- [Python Code Style](#python-code-style)
- [Commit Message Format](#commit-message-format)

---

### Python Code Style

- Follow PEP 8 guidelines
- Use type hints where appropriate
- Write docstrings for all public functions/classes
- Keep functions focused and small
- Use async/await for I/O operations

**Example:**
```python
async def get_server_info(self) -> Optional[dict]:
    """
    Get server info from rippled

    Returns:
        Server info dict or None on error
    """
    try:
        response = await self.request(ServerInfo())
        if response.is_successful():
            return response.result.get('info', {})
        return None
    except Exception as e:
        logger.error(f"Error getting server info: {e}")
        return None
```

### Commit Message Format

Use conventional commits:
```
<type>: <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Adding/updating tests
- `chore`: Maintenance tasks

**Examples:**
```
feat: Add trendline transformation to I/O Latency panel

Implements linear regression trend lines for early detection
of performance degradation over 24h windows.
```

---

# Testing

**In This Section:**
- [Running Tests](#running-tests)
- [Writing Tests](#writing-tests)

---

### Running Tests

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=src tests/

# Run specific test file
pytest tests/test_xrpl_client.py
```

### Writing Tests

- Write unit tests for new functions
- Write integration tests for API interactions
- Mock external dependencies (rippled, VictoriaMetrics)
- Aim for >80% code coverage

---

# Documentation

### When to Update Documentation

Update documentation when:
- Adding new features
- Changing configuration options
- Modifying metrics
- Discovering important implementation details (like WebSocket vs HTTP admin behavior)

### Documentation Files

- `README.md` - Project overview and quick start
- `DOCKER_ADVANCED.md` - Docker deployment guide
- `METRICS.md` - Metrics schema and descriptions
- `RIPPLED-CONFIG.md` - rippled configuration guide
- `docs/architecture/` - Architecture documentation
- `docs/research/` - Research notes and analysis

---

# Pull Request Process

1. **Create feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make changes following best practices**

3. **Commit regularly with good messages**

4. **Push to your fork:**
   ```bash
   git push origin feature/your-feature-name
   ```

5. **Create Pull Request on GitHub:**
   - Provide clear description
   - Reference related issues
   - Include screenshots for UI changes
   - Ensure tests pass

6. **Address review feedback**

7. **Squash commits if needed**

---

# Grafana Dashboard Development

**In This Section:**
- [Using Grafana Service Account](#using-grafana-service-account)
- [Dashboard Best Practices](#dashboard-best-practices)

---

### Using Grafana Service Account

For dashboard development, use a Grafana service account token:

1. **Create service account in Grafana UI:**
   - Settings → Service Accounts → Add service account
   - Give it Admin role (for development only)
   - Generate token

2. **Use token with Grafana API:**
   ```bash
   # Pull current dashboard
   curl -H "Authorization: Bearer <token>" \
     http://localhost:3000/api/dashboards/uid/<dashboard-uid>

   # Push updated dashboard
   curl -X POST \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d @dashboard.json \
     http://localhost:3000/api/dashboards/db
   ```

3. **Delete service account when done** (don't leave it in production)

### Dashboard Best Practices

- Test changes on development Grafana (port 3000)
- Use version control for dashboard JSON
- Document panel configurations
- Use variables for reusable queries
- Keep queries efficient

---

# Troubleshooting

### Common Issues

**Monitor won't start:**
- Check rippled is running and accessible
- Verify VictoriaMetrics is healthy
- Check environment variables in `.env`
- Review logs: `docker-compose logs -f monitor`

**No metrics appearing:**
- Verify rippled WebSocket connection
- Check HTTP admin API access
- Confirm VictoriaMetrics write endpoint
- Check firewall/network settings

**Dashboard shows "No data":**
- Verify metrics are being written: `curl http://localhost:8428/api/v1/query?query=xrpl_ledger_sequence`
- Check time range in Grafana
- Verify dashboard queries match metric names

---

# Getting Help

- **GitHub Issues:** https://github.com/realgrapedrop/xrpl-validator-dashboard/issues
- **Discussions:** https://github.com/realgrapedrop/xrpl-validator-dashboard/discussions
- **XRPL Docs:** https://xrpl.org/docs

---

# Code of Conduct

- Be respectful and constructive
- Focus on technical merit
- Welcome newcomers
- Give credit where due
- Follow open source best practices

---

# License

By contributing to XRPL Monitor, you agree that your contributions will be licensed under the MIT License.
