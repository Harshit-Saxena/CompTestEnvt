/**
 * @description MemoryOptimizer - Advanced memory optimization utilities
 * @author CompTestEnvt Team
 * @date 2024
 * @jira [SF-1] - Memory optimization utilities for Salesforce
 */
public with sharing class MemoryOptimizer {

    // Memory constants
    private static final Integer LARGE_COLLECTION_THRESHOLD = 1000;
    private static final Integer STRING_POOL_LIMIT = 100;

    /**
    * @description Optimization statistics
    */
    public class OptimizationStats {
        @AuraEnabled public Integer initialHeap {get; set;}
        @AuraEnabled public Integer finalHeap {get; set;}
        @AuraEnabled public Integer memorySaved {get; set;}
        @AuraEnabled public Decimal savingsPercent {get; set;}
        @AuraEnabled public List<String> optimizationsApplied {get; set;}
        @AuraEnabled public Long executionTime {get; set;}

        public OptimizationStats() {
            this.optimizationsApplied = new List<String>();
            this.initialHeap = Limits.getHeapSize();
        }

        public void finalize() {
            this.finalHeap = Limits.getHeapSize();
            this.memorySaved = this.initialHeap - this.finalHeap;
            if (this.initialHeap > 0) {
                this.savingsPercent = ((Decimal)this.memorySaved / this.initialHeap) * 100;
            }
        }
    }

    /**
    * @description Optimize SObject list by removing unnecessary fields
    * @param records List of SObjects to optimize
    * @param fieldsToKeep Set of field API names to retain
    * @return OptimizationStats with results
    */
    public static OptimizationStats optimizeSObjectList(
    List<SObject> records,
    Set<String> fieldsToKeep
    ) {
        OptimizationStats stats = new OptimizationStats();
        Long startTime = System.currentTimeMillis();

        if (records == null || records.isEmpty() || fieldsToKeep == null) {
            stats.executionTime = System.currentTimeMillis() - startTime;
            stats.finalize();
            return stats;
        }

        try {
            // For each record, create optimized version with only required fields
            List<SObject> optimizedRecords = new List<SObject>();

            for (SObject record : records) {
                Map<String, Object> fieldMap = record.getPopulatedFieldsAsMap();
                SObject optimizedRecord = record.getSObjectType().newSObject();

                for (String fieldName : fieldsToKeep) {
                    if (fieldMap.containsKey(fieldName)) {
                        optimizedRecord.put(fieldName, fieldMap.get(fieldName));
                    }
                }

                optimizedRecords.add(optimizedRecord);
            }

            // Replace original list
            records.clear();
            records.addAll(optimizedRecords);

            stats.optimizationsApplied.add('Removed unnecessary fields from ' + records.size() + ' records');

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'SObject optimization failed: ' + e.getMessage());
        }

        stats.executionTime = System.currentTimeMillis() - startTime;
        stats.finalize();
        return stats;
    }

    /**
    * @description Deduplicate strings in collections to reduce memory
    * @param strings List of strings to deduplicate
    * @return Integer number of duplicates removed
    */
    public static Integer deduplicateStrings(List<String> strings) {
        if (strings == null || strings.size() < 2) {
            return 0;
        }

        Map<String, String> stringPool = new Map<String, String>();
        Integer duplicatesRemoved = 0;

        for (Integer i = 0; i < strings.size(); i++) {
            String original = strings[i];

            if (original != null) {
                if (stringPool.containsKey(original)) {
                    // Reference existing string
                    strings[i] = stringPool.get(original);
                    duplicatesRemoved++;
                } else {
                    // Add to pool
                    stringPool.put(original, original);

                    // Limit pool size to prevent excessive memory use
                    if (stringPool.size() > STRING_POOL_LIMIT) {
                        stringPool.clear();
                        stringPool.put(original, original);
                    }
                }
            }
        }

        return duplicatesRemoved;
    }

    /**
    * @description Compress large map by removing null/empty values
    * @param dataMap Map to compress
    * @return Integer number of entries removed
    */
    public static Integer compressMap(Map<String, Object> dataMap) {
        if (dataMap == null || dataMap.isEmpty()) {
            return 0;
        }

        Set<String> keysToRemove = new Set<String>();

        for (String key : dataMap.keySet()) {
            Object value = dataMap.get(key);

            if (value == null ||
            (value instanceof String && String.isBlank((String)value)) ||
            (value instanceof List<Object> && ((List<Object>)value).isEmpty()) ||
            (value instanceof Set<Object> && ((Set<Object>)value).isEmpty()) ||
            (value instanceof Map<Object, Object> && ((Map<Object, Object>)value).isEmpty())) {

                keysToRemove.add(key);
            }
        }

        for (String key : keysToRemove) {
            dataMap.remove(key);
        }

        return keysToRemove.size();
    }

    /**
    * @description Split large collection into smaller chunks for processing
    * @param largeList Large list to split
    * @param chunkSize Size of each chunk
    * @return List of chunks
    */
    public static List<List<Object>> splitIntoChunks(List<Object> largeList, Integer chunkSize) {
        List<List<Object>> chunks = new List<List<Object>>();

        if (largeList == null || largeList.isEmpty()) {
            return chunks;
        }

        chunkSize = (chunkSize == null || chunkSize < 1) ? 100 : chunkSize;

        for (Integer i = 0; i < largeList.size(); i += chunkSize) {
            List<Object> chunk = new List<Object>();

            for (Integer j = i; j < Math.min(i + chunkSize, largeList.size()); j++) {
                chunk.add(largeList[j]);
            }

            chunks.add(chunk);

            // Monitor heap
            if (!HeapSizeManager.monitorHeap('Chunking at position ' + i)) {
                break;
            }
        }

        return chunks;
    }

    /**
    * @description Lazy load pattern for expensive objects
    */
    public class LazyLoader {
        private Map<String, Object> cache;
        private Map<String, LoaderFunction> loaders;

        public LazyLoader() {
            this.cache = new Map<String, Object>();
            this.loaders = new Map<String, LoaderFunction>();
        }

        /**
        * @description Register a loader function for a key
        */
        public void registerLoader(String key, LoaderFunction loader) {
            loaders.put(key, loader);
        }

        /**
        * @description Get value, loading if necessary
        */
        public Object get(String key) {
            if (!cache.containsKey(key)) {
                if (loaders.containsKey(key)) {
                    // Check heap before loading
                    if (HeapSizeManager.hasEnoughHeap(100000)) { // 100KB buffer
                    cache.put(key, loaders.get(key).load());
                } else {
                    System.debug('Insufficient heap for lazy loading: ' + key);
                    return null;
                }
            }
        }
        return cache.get(key);
    }

    /**
    * @description Clear specific cached value
    */
    public void evict(String key) {
        cache.remove(key);
    }

    /**
    * @description Clear all cached values
    */
    public void evictAll() {
        cache.clear();
    }
}

/**
* @description Interface for lazy loading functions
*/
public interface LoaderFunction {
    Object load();
}

/**
* @description Memory-efficient string builder
*/
public class EfficientStringBuilder {
    private List<String> parts;
    private Integer estimatedSize;
    private static final Integer MAX_PARTS = 1000;

    public EfficientStringBuilder() {
        this.parts = new List<String>();
        this.estimatedSize = 0;
    }

    /**
    * @description Append string to builder
    */
    public EfficientStringBuilder append(String str) {
        if (str != null && parts.size() < MAX_PARTS) {
            parts.add(str);
            estimatedSize += str.length();

            // Check if we should consolidate
            if (parts.size() % 100 == 0) {
                consolidate();
            }
        }
        return this;
    }

    /**
    * @description Consolidate parts to reduce memory overhead
    */
    private void consolidate() {
        if (parts.size() > 10) {
            String consolidated = String.join(parts, '');
            parts.clear();
            parts.add(consolidated);
        }
    }

    /**
    * @description Get final string
    */
    public String toString() {
        if (parts.isEmpty()) {
            return '';
        }
        return String.join(parts, '');
    }

    /**
    * @description Clear builder
    */
    public void clear() {
        parts.clear();
        estimatedSize = 0;
    }

    /**
    * @description Get estimated size
    */
    public Integer getEstimatedSize() {
        return estimatedSize;
    }
}

/**
* @description Optimize JSON string by removing whitespace and formatting
* @param jsonString JSON string to optimize
* @return Optimized JSON string
*/
public static String optimizeJson(String jsonString) {
    if (String.isBlank(jsonString)) {
        return jsonString;
    }

    try {
        // Parse and re-serialize without formatting
        Object parsed = JSON.deserializeUntyped(jsonString);
        return JSON.serialize(parsed);
    } catch (Exception e) {
        System.debug(LoggingLevel.WARN, 'JSON optimization failed: ' + e.getMessage());
        return jsonString;
    }
}

/**
* @description Cache manager with size limits
*/
public class BoundedCache {
    private Map<String, Object> cache;
    private List<String> accessOrder;
    private Integer maxSize;

    public BoundedCache(Integer maxSize) {
        this.cache = new Map<String, Object>();
        this.accessOrder = new List<String>();
        this.maxSize = (maxSize == null || maxSize < 1) ? 100 : maxSize;
    }

    /**
    * @description Put value in cache
    */
    public void put(String key, Object value) {
        // Remove if exists to update access order
        if (cache.containsKey(key)) {
            accessOrder.remove(accessOrder.indexOf(key));
        }

        // Add to cache
        cache.put(key, value);
        accessOrder.add(key);

        // Evict oldest if over limit
        if (cache.size() > maxSize) {
            String oldest = accessOrder.remove(0);
            cache.remove(oldest);
        }
    }

    /**
    * @description Get value from cache
    */
    public Object get(String key) {
        if (cache.containsKey(key)) {
            // Update access order
            accessOrder.remove(accessOrder.indexOf(key));
            accessOrder.add(key);
            return cache.get(key);
        }
        return null;
    }

    /**
    * @description Clear cache
    */
    public void clear() {
        cache.clear();
        accessOrder.clear();
    }

    /**
    * @description Get cache size
    */
    public Integer size() {
        return cache.size();
    }
}
}
