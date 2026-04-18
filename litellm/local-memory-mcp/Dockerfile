FROM cunicopia/local-memory-mcp:postgres

COPY docker-entrypoint-external.sh /docker-entrypoint-external.sh
RUN chmod +x /docker-entrypoint-external.sh

ENTRYPOINT ["/docker-entrypoint-external.sh"]
