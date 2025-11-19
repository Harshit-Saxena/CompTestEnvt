/**
 * @description LargeDataProcessor - Handles large data sets without async Apex
 * @author CompTestEnvt Team
 * @date 2024
 */
public with sharing class LargeDataProcessor {

    // Processing configuration
    private static final Integer DEFAULT_CHUNK_SIZE = 200;
    private static final Integer MAX_ITERATIONS = 100; // Prevent infinite loops
    private static final Integer HEAP_CHECK_FREQUENCY = 5; // Check heap every N iterations

    /**
     * @description Wrapper for paginated results
     */
    public class PaginatedResult {
        @AuraEnabled public List<SObject> records {get; set;}
        @AuraEnabled public Integer totalRecords {get; set;}
        @AuraEnabled public Integer currentOffset {get; set;}
        @AuraEnabled public Integer pageSize {get; set;}
        @AuraEnabled public Boolean hasNext {get; set;}
        @AuraEnabled public Boolean hasPrevious {get; set;}
        @AuraEnabled public HeapSizeManager.HeapStats heapStats {get; set;}
        @AuraEnabled public Long processingTime {get; set;}
        @AuraEnabled public String errorMessage {get; set;}

        public PaginatedResult() {
            this.records = new List<SObject>();
            this.currentOffset = 0;
            this.pageSize = DEFAULT_CHUNK_SIZE;
            this.hasNext = false;
            this.hasPrevious = false;
        }
    }

    /**
     * @description Configuration for processing large data sets
     */
    public class ProcessingConfig {
        public String query {get; set;}
        public Integer chunkSize {get; set;}
        public Integer maxRecords {get; set;}
        public Boolean monitorHeap {get; set;}
        public Boolean optimizeMemory {get; set;}
        public Set<String> fieldsToKeep {get; set;}

        public ProcessingConfig() {
            this.chunkSize = DEFAULT_CHUNK_SIZE;
            this.maxRecords = 50000; // Default max
            this.monitorHeap = true;
            this.optimizeMemory = true;
            this.fieldsToKeep = new Set<String>();
        }
    }

    /**
     * @description Stream-like processor for large data sets
     */
    public class DataStream {
        private String baseQuery;
        private Integer currentOffset;
        private Integer chunkSize;
        private Boolean hasMore;
        private HeapSizeManager.HeapStats lastHeapStats;

        public DataStream(String query, Integer chunkSize) {
            this.baseQuery = query;
            this.currentOffset = 0;
            this.chunkSize = (chunkSize == null) ? DEFAULT_CHUNK_SIZE : chunkSize;
            this.hasMore = true;
        }

        /**
         * @description Get next batch of records
         * @return List of SObjects or empty list
         */
        public List<SObject> next() {
            if (!hasMore) {
                return new List<SObject>();
            }

            // Check heap before querying
            lastHeapStats = HeapSizeManager.getCurrentHeapStats();
            if (lastHeapStats.status == 'CRITICAL') {
                hasMore = false;
                return new List<SObject>();
            }

            // Adjust chunk size based on available heap
            Integer adjustedSize = Math.min(
                chunkSize,
                lastHeapStats.recommendedBatchSize
            );

            try {
                String query = baseQuery + ' LIMIT ' + adjustedSize + ' OFFSET ' + currentOffset;
                List<SObject> records = Database.query(query);

                if (records.size() < adjustedSize) {
                    hasMore = false;
                }

                currentOffset += records.size();
                return records;

            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'DataStream query failed: ' + e.getMessage());
                hasMore = false;
                return new List<SObject>();
            }
        }

        public Boolean hasNext() {
            return hasMore;
        }

        public Integer getOffset() {
            return currentOffset;
        }

        public HeapSizeManager.HeapStats getLastHeapStats() {
            return lastHeapStats;
        }
    }

    /**
     * @description Get paginated records with heap optimization
     * @param query String SOQL query (without LIMIT/OFFSET)
     * @param pageNumber Integer page number (1-based)
     * @param pageSize Integer records per page
     * @return PaginatedResult with records and metadata
     */
    public static PaginatedResult getPaginatedRecords(
        String query,
        Integer pageNumber,
        Integer pageSize
    ) {
        Long startTime = System.currentTimeMillis();
        PaginatedResult result = new PaginatedResult();

        try {
            // Validate inputs
            pageNumber = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
            pageSize = (pageSize == null || pageSize < 1) ? DEFAULT_CHUNK_SIZE : pageSize;

            // Check heap status first
            result.heapStats = HeapSizeManager.getCurrentHeapStats();
            if (result.heapStats.status == 'CRITICAL') {
                result.errorMessage = 'Insufficient heap space for query';
                return result;
            }

            // Adjust page size based on heap
            pageSize = Math.min(pageSize, result.heapStats.recommendedBatchSize);

            // Calculate offset
            Integer offset = (pageNumber - 1) * pageSize;

            // Execute count query for total records (with timeout)
            result.totalRecords = getRecordCount(query);

            // Execute main query
            String paginatedQuery = query + ' LIMIT ' + pageSize + ' OFFSET ' + offset;
            result.records = Database.query(paginatedQuery);

            // Set pagination metadata
            result.currentOffset = offset;
            result.pageSize = pageSize;
            result.hasNext = (offset + result.records.size()) < result.totalRecords;
            result.hasPrevious = pageNumber > 1;

            // Update heap stats after query
            result.heapStats = HeapSizeManager.getCurrentHeapStats();

        } catch (Exception e) {
            result.errorMessage = 'Query failed: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, result.errorMessage);
        }

        result.processingTime = System.currentTimeMillis() - startTime;
        return result;
    }

    /**
     * @description Process records in chunks with custom logic
     * @param config ProcessingConfig configuration object
     * @param processor Custom processor implementation
     * @return Integer total records processed
     */
    public static Integer processInChunks(
        ProcessingConfig config,
        ChunkProcessor processor
    ) {
        Integer totalProcessed = 0;
        Integer iterations = 0;
        DataStream stream = new DataStream(config.query, config.chunkSize);

        while (stream.hasNext() && iterations < MAX_ITERATIONS) {
            List<SObject> chunk = stream.next();

            if (chunk.isEmpty()) {
                break;
            }

            // Process the chunk
            try {
                processor.processChunk(chunk, iterations);
                totalProcessed += chunk.size();
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'Chunk processing failed at iteration ' + iterations + ': ' + e.getMessage());
                break;
            }

            // Memory optimization
            if (config.optimizeMemory) {
                chunk.clear();
            }

            // Heap monitoring
            if (config.monitorHeap && iterations % HEAP_CHECK_FREQUENCY == 0) {
                HeapSizeManager.HeapStats stats = stream.getLastHeapStats();
                System.debug('Heap usage at iteration ' + iterations + ': ' +
                           HeapSizeManager.formatBytes(stats.currentHeapSize));

                if (stats.status == 'CRITICAL') {
                    System.debug('Stopping due to critical heap usage');
                    break;
                }
            }

            iterations++;

            // Check if we've reached max records
            if (totalProcessed >= config.maxRecords) {
                break;
            }
        }

        return totalProcessed;
    }

    /**
     * @description Efficiently aggregate large data sets
     * @param query String SOQL query
     * @param aggregator Custom aggregator implementation
     * @return Object aggregated result
     */
    public static Object aggregateLargeDataSet(
        String query,
        DataAggregator aggregator
    ) {
        DataStream stream = new DataStream(query, DEFAULT_CHUNK_SIZE);
        aggregator.initialize();

        while (stream.hasNext()) {
            List<SObject> chunk = stream.next();

            if (chunk.isEmpty()) {
                break;
            }

            // Aggregate the chunk
            aggregator.aggregateChunk(chunk);

            // Clear chunk to free memory
            chunk.clear();

            // Check heap periodically
            if (stream.getOffset() % 1000 == 0) {
                if (!HeapSizeManager.monitorHeap('Aggregation at offset ' + stream.getOffset())) {
                    break;
                }
            }
        }

        return aggregator.getResult();
    }

    /**
     * @description Memory-efficient record transformation
     * @param sourceQuery String query for source records
     * @param transformer Record transformer implementation
     * @return List of transformed records
     */
    public static List<Object> transformLargeDataSet(
        String sourceQuery,
        RecordTransformer transformer
    ) {
        List<Object> results = new List<Object>();
        DataStream stream = new DataStream(sourceQuery, DEFAULT_CHUNK_SIZE);

        while (stream.hasNext()) {
            List<SObject> chunk = stream.next();

            for (SObject record : chunk) {
                // Check if we have heap space for transformation
                if (!HeapSizeManager.hasEnoughHeap(10240)) { // 10KB buffer
                    System.debug('Insufficient heap for transformation');
                    return results;
                }

                Object transformed = transformer.transform(record);
                if (transformed != null) {
                    results.add(transformed);
                }
            }

            // Clear source chunk
            chunk.clear();
        }

        return results;
    }

    /**
     * @description Get count of records with timeout
     * @param baseQuery String query without COUNT()
     * @return Integer record count or -1 if timeout
     */
    private static Integer getRecordCount(String baseQuery) {
        Long startTime = System.currentTimeMillis();
        Long timeout = 5000; // 5 second timeout for count

        try {
            // Extract FROM clause
            String countQuery = 'SELECT COUNT() ' +
                baseQuery.substringAfter('FROM').substringBefore('ORDER BY');

            Integer count = Database.countQuery(countQuery);

            Long elapsed = System.currentTimeMillis() - startTime;
            if (elapsed > timeout) {
                System.debug('Count query timeout: ' + elapsed + 'ms');
                return -1;
            }

            return count;

        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Count query failed: ' + e.getMessage());
            return -1;
        }
    }

    /**
     * @description Interface for chunk processing
     */
    public interface ChunkProcessor {
        void processChunk(List<SObject> records, Integer chunkNumber);
    }

    /**
     * @description Interface for data aggregation
     */
    public interface DataAggregator {
        void initialize();
        void aggregateChunk(List<SObject> records);
        Object getResult();
    }

    /**
     * @description Interface for record transformation
     */
    public interface RecordTransformer {
        Object transform(SObject record);
    }
}