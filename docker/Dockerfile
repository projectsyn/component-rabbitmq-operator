FROM python:3.14-slim

# Create non-root user for security
RUN groupadd -r prober && useradd -r -g prober prober

# Set working directory
WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir pika==1.3.2 prometheus_client==0.17.1 pyopenssl==23.2.0

# Copy application code
COPY docker/prober.py .

# Change ownership to non-root user
RUN chown -R prober:prober /app

# Switch to non-root user
USER prober

# Expose metrics port
EXPOSE 8080

# Run the application
CMD ["python", "prober.py"]
