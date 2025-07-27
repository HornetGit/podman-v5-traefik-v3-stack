FROM postgres:alpine

# COPY debug.sh /debug.sh
# RUN chmod +x /debug.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
 
ENTRYPOINT ["/entrypoint.sh"]