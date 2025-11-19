/**
 * @description HeapSizeManager - Comprehensive utility class for managing heap size and memory optimization
 * @author CompTestEnvt Team
 * @date 2024
 */
public with sharing class HeapSizeManager {

    // Constants for memory thresholds (in bytes)
    private static final Integer ONE_MB = 1048576; // 1 MB in bytes
    private static final Integer CRITICAL_HEAP_THRESHOLD = 2 * ONE_MB; // 2 MB
    private static final Integer WARNING_HEAP_THRESHOLD = 5 * ONE_MB; // 5 MB
    private static final Integer SAFE_HEAP_BUFFER = 500000; // 500 KB safety buffer

    // Batch processing constants
    private static final Integer DEFAULT_BATCH_SIZE = 200;
    private static final Integer MIN_BATCH_SIZE = 10;
    private static final Integer MAX_BATCH_SIZE = 2000;

    /**
     * @description Inner class to hold heap statistics
     */
    public class HeapStats {
        @AuraEnabled public Integer currentHeapSize {get; set;}
        @AuraEnabled public Integer maxHeapSize {get; set;}
        @AuraEnabled public Integer availableHeap {get; set;}
        @AuraEnabled public Decimal heapUsagePercent {get; set;}
        @AuraEnabled public String status {get; set;} // SAFE, WARNING, CRITICAL
        @AuraEnabled public Integer recommendedBatchSize {get; set;}
        @AuraEnabled public Long timestamp {get; set;}

        public HeapStats() {
            this.timestamp = System.currentTimeMillis();
        }
    }

    /**
     * @description Memory optimization result wrapper
     */
    public class OptimizationResult {
        @AuraEnabled public Integer recordsProcessed {get; set;}
        @AuraEnabled public Integer batchesCompleted {get; set;}
        @AuraEnabled public Integer heapSaved {get; set;}
        @AuraEnabled public List<String> optimizationActions {get; set;}
        @AuraEnabled public Boolean success {get; set;}
        @AuraEnabled public String errorMessage {get; set;}

        public OptimizationResult() {
            this.optimizationActions = new List<String>();
            this.recordsProcessed = 0;
            this.batchesCompleted = 0;
            this.heapSaved = 0;
            this.success = true;
        }
    }

    /**
     * @description Get current heap statistics
     * @return HeapStats object with current memory information
     */
    public static HeapStats getCurrentHeapStats() {
        HeapStats stats = new HeapStats();

        stats.currentHeapSize = Limits.getHeapSize();
        stats.maxHeapSize = Limits.getLimitHeapSize();
        stats.availableHeap = stats.maxHeapSize - stats.currentHeapSize;

        if (stats.maxHeapSize > 0) {
            stats.heapUsagePercent = ((Decimal)stats.currentHeapSize / stats.maxHeapSize) * 100;
        }

        // Determine status
        if (stats.availableHeap < CRITICAL_HEAP_THRESHOLD) {
            stats.status = 'CRITICAL';
        } else if (stats.availableHeap < WARNING_HEAP_THRESHOLD) {
            stats.status = 'WARNING';
        } else {
            stats.status = 'SAFE';
        }

        // Calculate recommended batch size based on available heap
        stats.recommendedBatchSize = calculateOptimalBatchSize(stats.availableHeap);

        return stats;
    }

    /**
     * @description Monitor heap usage and log if threshold exceeded
     * @param operation String describing the current operation
     * @return Boolean indicating if heap is within safe limits
     */
    public static Boolean monitorHeap(String operation) {
        HeapStats stats = getCurrentHeapStats();

        if (stats.status == 'CRITICAL') {
            System.debug(LoggingLevel.ERROR,
                'CRITICAL HEAP: Operation [' + operation + '] - Used: ' +
                formatBytes(stats.currentHeapSize) + ' of ' +
                formatBytes(stats.maxHeapSize));
            return false;
        } else if (stats.status == 'WARNING') {
            System.debug(LoggingLevel.WARN,
                'WARNING HEAP: Operation [' + operation + '] - Used: ' +
                formatBytes(stats.currentHeapSize) + ' of ' +
                formatBytes(stats.maxHeapSize));
        }

        return true;
    }

    /**
     * @description Calculate optimal batch size based on available heap
     * @param availableHeap Integer available heap in bytes
     * @return Integer recommended batch size
     */
    public static Integer calculateOptimalBatchSize(Integer availableHeap) {
        // Estimate ~10KB per record (conservative estimate)
        Integer estimatedRecordSize = 10240; // 10 KB

        // Use 70% of available heap for safety
        Integer usableHeap = (Integer)(availableHeap * 0.7);

        Integer optimalSize = usableHeap / estimatedRecordSize;

        // Apply min and max constraints
        if (optimalSize < MIN_BATCH_SIZE) {
            return MIN_BATCH_SIZE;
        } else if (optimalSize > MAX_BATCH_SIZE) {
            return MAX_BATCH_SIZE;
        }

        return optimalSize;
    }

    /**
     * @description Process large record sets in memory-efficient batches
     * @param query String SOQL query to execute
     * @param processor IRecordProcessor implementation for processing records
     * @param maxRecords Integer maximum records to process (optional)
     * @return OptimizationResult with processing details
     */
    public static OptimizationResult processBatchedRecords(
        String query,
        IRecordProcessor processor,
        Integer maxRecords
    ) {
        OptimizationResult result = new OptimizationResult();
        Integer offset = 0;
        Integer totalProcessed = 0;
        maxRecords = (maxRecords == null) ? Integer.valueOf(2147483647) : maxRecords; // Max integer if null

        try {
            while (totalProcessed < maxRecords) {
                // Get current heap stats and determine batch size
                HeapStats stats = getCurrentHeapStats();
                Integer batchSize = Math.min(
                    stats.recommendedBatchSize,
                    maxRecords - totalProcessed
                );

                if (stats.status == 'CRITICAL') {
                    result.optimizationActions.add('Stopped processing due to critical heap');
                    break;
                }

                // Build query with limit and offset
                String batchQuery = query + ' LIMIT ' + batchSize + ' OFFSET ' + offset;

                // Execute query and process records
                List<SObject> records = Database.query(batchQuery);

                if (records.isEmpty()) {
                    break; // No more records
                }

                // Process the batch
                processor.process(records);

                totalProcessed += records.size();
                offset += batchSize;
                result.batchesCompleted++;

                // Clear the list to free memory
                records.clear();

                // Force garbage collection hint
                if (result.batchesCompleted % 5 == 0) {
                    System.debug('Processed ' + totalProcessed + ' records in ' +
                               result.batchesCompleted + ' batches');
                }
            }

            result.recordsProcessed = totalProcessed;
            result.success = true;

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage() + ' at line ' + e.getLineNumber();
            System.debug(LoggingLevel.ERROR, 'Batch processing failed: ' + result.errorMessage);
        }

        return result;
    }

    /**
     * @description Clear collection and free memory
     * @param collection Object collection to clear (List, Set, or Map)
     */
    public static void clearCollection(Object collection) {
        if (collection == null) return;

        Integer heapBefore = Limits.getHeapSize();

        if (collection instanceof List<Object>) {
            ((List<Object>)collection).clear();
        } else if (collection instanceof Set<Object>) {
            ((Set<Object>)collection).clear();
        } else if (collection instanceof Map<Object, Object>) {
            ((Map<Object, Object>)collection).clear();
        }

        Integer heapAfter = Limits.getHeapSize();
        System.debug('Memory freed: ' + formatBytes(heapBefore - heapAfter));
    }

    /**
     * @description Optimize large string operations
     * @param largeString String to process
     * @param chunkSize Integer size of each chunk
     * @return List of string chunks
     */
    public static List<String> chunkString(String largeString, Integer chunkSize) {
        List<String> chunks = new List<String>();

        if (String.isBlank(largeString)) {
            return chunks;
        }

        Integer stringLength = largeString.length();
        Integer position = 0;

        while (position < stringLength) {
            Integer endPosition = Math.min(position + chunkSize, stringLength);
            chunks.add(largeString.substring(position, endPosition));
            position = endPosition;

            // Monitor heap after each chunk
            if (!monitorHeap('String chunking')) {
                System.debug('Stopping string chunking due to heap constraints');
                break;
            }
        }

        return chunks;
    }

    /**
     * @description Safely query records with heap monitoring
     * @param query String SOQL query
     * @param limitSize Integer max records to return
     * @return List of SObjects or empty list if heap exceeded
     */
    public static List<SObject> safeQuery(String query, Integer limitSize) {
        HeapStats stats = getCurrentHeapStats();

        if (stats.status == 'CRITICAL') {
            System.debug(LoggingLevel.ERROR, 'Cannot execute query - heap critical');
            return new List<SObject>();
        }

        // Adjust limit based on available heap
        Integer safeLimit = Math.min(limitSize, stats.recommendedBatchSize);

        try {
            String safeQueryString = query + ' LIMIT ' + safeLimit;
            return Database.query(safeQueryString);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Safe query failed: ' + e.getMessage());
            return new List<SObject>();
        }
    }

    /**
     * @description Format bytes to human readable format
     * @param bytes Integer number of bytes
     * @return String formatted size (e.g., "2.5 MB")
     */
    public static String formatBytes(Integer bytes) {
        if (bytes < 1024) {
            return bytes + ' B';
        } else if (bytes < ONE_MB) {
            return String.valueOf((Decimal)bytes / 1024).substring(0, 4) + ' KB';
        } else {
            return String.valueOf((Decimal)bytes / ONE_MB).substring(0, 4) + ' MB';
        }
    }

    /**
     * @description Check if we have enough heap for an operation
     * @param requiredHeap Integer required heap in bytes
     * @return Boolean true if enough heap available
     */
    public static Boolean hasEnoughHeap(Integer requiredHeap) {
        HeapStats stats = getCurrentHeapStats();
        return stats.availableHeap > (requiredHeap + SAFE_HEAP_BUFFER);
    }

    /**
     * @description Optimize map for memory efficiency
     * @param sourceMap Map to optimize
     * @param keepKeys Set of keys to retain (null = keep all)
     * @return Integer bytes saved
     */
    public static Integer optimizeMap(Map<String, Object> sourceMap, Set<String> keepKeys) {
        if (sourceMap == null || sourceMap.isEmpty()) {
            return 0;
        }

        Integer heapBefore = Limits.getHeapSize();

        if (keepKeys != null) {
            // Remove unwanted keys
            Set<String> keysToRemove = new Set<String>();
            for (String key : sourceMap.keySet()) {
                if (!keepKeys.contains(key)) {
                    keysToRemove.add(key);
                }
            }

            for (String key : keysToRemove) {
                sourceMap.remove(key);
            }
        }

        Integer heapAfter = Limits.getHeapSize();
        return heapBefore - heapAfter;
    }

    /**
     * @description Interface for record processing
     */
    public interface IRecordProcessor {
        void process(List<SObject> records);
    }
}