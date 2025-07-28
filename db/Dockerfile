FROM postgres:alpine

# COPY debug.sh /debug.sh
# RUN chmod +x /debug.sh

#  health check
# HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
#   CMD pg_isready -U $POSTGRES_USER -d $POSTGRES_DB || exit 1

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]