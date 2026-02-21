FROM python:3.14-alpine

WORKDIR /app

# Ensure unbuffered output for Docker logging
# Set PYTHONPATH so absolute imports work naturally
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Create non-root user for security
RUN addgroup -g 1001 syncer && \
    adduser -D -u 1001 -G syncer syncer && \
    chown -R syncer:syncer /app

# Copy only the necessary source files for runtime
COPY --chown=syncer:syncer src/ ./src/

# Switch to non-root user
USER syncer

# Add health check to verify service is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import logging; logging.info('Health check OK')" || exit 1

# Run the imperative shell as a module
CMD ["python", "-m", "src.main"]