/**
 * @description Test class for heap management utilities
 * @author CompTestEnvt Team
 * @date 2024
 * @jira [SF-1] - Test coverage for heap management utilities
 */
@IsTest
private with sharing class HeapManagementTest {

    @TestSetup
    static void setup() {
        // Create test accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            accounts.add(new Account(
            Name = 'Test Account ' + i,
            Phone = '555-' + String.valueOf(1000 + i),
            BillingCity = 'Test City',
            BillingState = 'TS',
            BillingCountry = 'Test Country',
            Type = Math.mod(i, 3) == 0 ? 'Customer' : 'Prospect',
            Industry = Math.mod(i, 2) == 0 ? 'Technology' : 'Healthcare'
            ));
        }
        insert accounts;
    }

    /**
    * @description Test HeapSizeManager heap statistics
    */
    @IsTest
    static void testGetCurrentHeapStats() {
        Test.startTest();

        HeapSizeManager.HeapStats stats = HeapSizeManager.getCurrentHeapStats();

        Test.stopTest();

        System.assertNotEquals(null, stats, 'HeapStats should not be null');
        System.assert(stats.currentHeapSize > 0, 'Current heap size should be greater than 0');
        System.assert(stats.maxHeapSize > 0, 'Max heap size should be greater than 0');
        System.assert(stats.availableHeap > 0, 'Available heap should be greater than 0');
        System.assertNotEquals(null, stats.status, 'Status should not be null');
        System.assert(stats.recommendedBatchSize > 0, 'Recommended batch size should be greater than 0');
    }

    /**
    * @description Test heap monitoring
    */
    @IsTest
    static void testMonitorHeap() {
        Test.startTest();

        Boolean result = HeapSizeManager.monitorHeap('Test Operation');

        Test.stopTest();

        System.assertEquals(true, result, 'Heap monitoring should return true for normal operations');
    }

    /**
    * @description Test optimal batch size calculation
    */
    @IsTest
    static void testCalculateOptimalBatchSize() {
        Test.startTest();

        Integer smallHeap = 100000; // 100KB
        Integer mediumHeap = 5000000; // 5MB
        Integer largeHeap = 50000000; // 50MB

        Integer smallBatch = HeapSizeManager.calculateOptimalBatchSize(smallHeap);
        Integer mediumBatch = HeapSizeManager.calculateOptimalBatchSize(mediumHeap);
        Integer largeBatch = HeapSizeManager.calculateOptimalBatchSize(largeHeap);

        Test.stopTest();

        System.assertEquals(10, smallBatch, 'Small heap should return minimum batch size');
        System.assert(mediumBatch > smallBatch, 'Medium batch should be larger than small');
        System.assert(largeBatch > mediumBatch, 'Large batch should be larger than medium');
    }

    /**
    * @description Test safe query functionality
    */
    @IsTest
    static void testSafeQuery() {
        Test.startTest();

        String query = 'SELECT Id, Name FROM Account';
        List<SObject> results = HeapSizeManager.safeQuery(query, 50);

        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() <= 50, 'Results should respect limit');
    }

    /**
    * @description Test format bytes utility
    */
    @IsTest
    static void testFormatBytes() {
        Test.startTest();

        String bytes = HeapSizeManager.formatBytes(512);
        String kb = HeapSizeManager.formatBytes(10240);
        String mb = HeapSizeManager.formatBytes(5242880);

        Test.stopTest();

        System.assert(bytes.contains('B'), 'Small values should show bytes');
        System.assert(kb.contains('KB'), 'Medium values should show KB');
        System.assert(mb.contains('MB'), 'Large values should show MB');
    }

    /**
    * @description Test LargeDataProcessor paginated records
    */
    @IsTest
    static void testGetPaginatedRecords() {
        Test.startTest();

        String query = 'SELECT Id, Name, Phone FROM Account';
        LargeDataProcessor.PaginatedResult result =
        LargeDataProcessor.getPaginatedRecords(query, 1, 50);

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.records.size() <= 50, 'Should respect page size');
        System.assertEquals(0, result.currentOffset, 'First page offset should be 0');
        System.assertNotEquals(null, result.heapStats, 'Heap stats should be included');
    }

    /**
    * @description Test DataStream functionality
    */
    @IsTest
    static void testDataStream() {
        Test.startTest();

        String query = 'SELECT Id, Name FROM Account';
        LargeDataProcessor.DataStream stream = new LargeDataProcessor.DataStream(query, 50);

        List<SObject> firstBatch = stream.next();
        Boolean hasMore = stream.hasNext();
        Integer offset = stream.getOffset();

        Test.stopTest();

        System.assertNotEquals(null, firstBatch, 'First batch should not be null');
        System.assert(firstBatch.size() <= 50, 'Batch size should respect limit');
        System.assert(offset > 0, 'Offset should advance after next()');
    }

    /**
    * @description Test chunk processing
    */
    @IsTest
    static void testProcessInChunks() {
        Test.startTest();

        LargeDataProcessor.ProcessingConfig config = new LargeDataProcessor.ProcessingConfig();
        config.query = 'SELECT Id, Name FROM Account';
        config.chunkSize = 50;
        config.maxRecords = 100;

        TestChunkProcessor processor = new TestChunkProcessor();
        Integer processed = LargeDataProcessor.processInChunks(config, processor);

        Test.stopTest();

        System.assert(processed > 0, 'Should process some records');
        System.assert(processed <= 100, 'Should respect max records');
        System.assert(processor.chunksProcessed > 0, 'Should process at least one chunk');
    }

    /**
    * @description Test MemoryOptimizer SObject optimization
    */
    @IsTest
    static void testOptimizeSObjectList() {
        List<Account> accounts = [SELECT Id, Name, Phone, BillingCity, Type FROM Account LIMIT 50];
        Set<String> fieldsToKeep = new Set<String>{'Id', 'Name'};

        Test.startTest();

        MemoryOptimizer.OptimizationStats stats =
        MemoryOptimizer.optimizeSObjectList(accounts, fieldsToKeep);

        Test.stopTest();

        System.assertNotEquals(null, stats, 'Stats should not be null');
        System.assert(stats.optimizationsApplied.size() > 0, 'Should have optimization actions');
    }

    /**
    * @description Test string deduplication
    */
    @IsTest
    static void testDeduplicateStrings() {
        List<String> strings = new List<String>();
        for (Integer i = 0; i < 100; i++) {
            strings.add('Test String ' + Math.mod(i, 10)); // Create duplicates
        }

        Test.startTest();

        Integer duplicatesRemoved = MemoryOptimizer.deduplicateStrings(strings);

        Test.stopTest();

        System.assert(duplicatesRemoved > 0, 'Should remove some duplicates');
    }

    /**
    * @description Test map compression
    */
    @IsTest
    static void testCompressMap() {
        Map<String, Object> testMap = new Map<String, Object>{
            'key1' => 'value1',
            'key2' => null,
            'key3' => '',
            'key4' => new List<String>(),
            'key5' => 'value5'
        };

        Test.startTest();

        Integer removed = MemoryOptimizer.compressMap(testMap);

        Test.stopTest();

        System.assertEquals(3, removed, 'Should remove 3 empty/null entries');
        System.assertEquals(2, testMap.size(), 'Map should have 2 remaining entries');
    }

    /**
    * @description Test lazy loader
    */
    @IsTest
    static void testLazyLoader() {
        Test.startTest();

        MemoryOptimizer.LazyLoader loader = new MemoryOptimizer.LazyLoader();
        TestLoaderFunction loaderFunc = new TestLoaderFunction();
        loader.registerLoader('test', loaderFunc);

        Object firstCall = loader.get('test');
        Object secondCall = loader.get('test');

        loader.evict('test');
        Object thirdCall = loader.get('test');

        Test.stopTest();

        System.assertNotEquals(null, firstCall, 'First call should return value');
        System.assertEquals(firstCall, secondCall, 'Second call should return cached value');
        System.assertEquals(1, loaderFunc.loadCount, 'Should load only once for cached calls');
    }

    /**
    * @description Test efficient string builder
    */
    @IsTest
    static void testEfficientStringBuilder() {
        Test.startTest();

        MemoryOptimizer.EfficientStringBuilder builder = new MemoryOptimizer.EfficientStringBuilder();
        builder.append('Hello')
        .append(' ')
        .append('World');

        String result = builder.toString();
        Integer estimatedSize = builder.getEstimatedSize();

        Test.stopTest();

        System.assertEquals('Hello World', result, 'Should build correct string');
        System.assertEquals(11, estimatedSize, 'Should track size correctly');
    }

    /**
    * @description Test bounded cache
    */
    @IsTest
    static void testBoundedCache() {
        Test.startTest();

        MemoryOptimizer.BoundedCache cache = new MemoryOptimizer.BoundedCache(3);

        cache.put('key1', 'value1');
        cache.put('key2', 'value2');
        cache.put('key3', 'value3');
        cache.put('key4', 'value4'); // Should evict key1

        Object value1 = cache.get('key1');
        Object value4 = cache.get('key4');

        Test.stopTest();

        System.assertEquals(null, value1, 'key1 should be evicted');
        System.assertEquals('value4', value4, 'key4 should be present');
        System.assertEquals(3, cache.size(), 'Cache size should not exceed limit');
    }

    /**
    * @description Test chunk splitting
    */
    @IsTest
    static void testSplitIntoChunks() {
        List<Object> largeList = new List<Object>();
        for (Integer i = 0; i < 250; i++) {
            largeList.add('Item ' + i);
        }

        Test.startTest();

        List<List<Object>> chunks = MemoryOptimizer.splitIntoChunks(largeList, 50);

        Test.stopTest();

        System.assertEquals(5, chunks.size(), 'Should create 5 chunks');
        System.assertEquals(50, chunks[0].size(), 'First chunk should have 50 items');
        System.assertEquals(50, chunks[4].size(), 'Last chunk should have 50 items');
    }

    /**
    * @description Test JSON optimization
    */
    @IsTest
    static void testOptimizeJson() {
        String prettyJson = '{\n  "name": "test",\n  "value": 123\n}';

        Test.startTest();

        String optimized = MemoryOptimizer.optimizeJson(prettyJson);

        Test.stopTest();

        System.assert(optimized.length() < prettyJson.length(), 'Optimized JSON should be smaller');
        System.assert(!optimized.contains('\n'), 'Optimized JSON should not have newlines');
    }

    // Test helper classes

    public with sharing class TestChunkProcessor implements LargeDataProcessor.ChunkProcessor {
        public Integer chunksProcessed = 0;
        public Integer totalRecords = 0;

        public void processChunk(List<SObject> records, Integer chunkNumber) {
            chunksProcessed++;
            totalRecords += records.size();
        }
    }

    public class TestLoaderFunction implements MemoryOptimizer.LoaderFunction {
        public Integer loadCount = 0;

        public Object load() {
            loadCount++;
            return 'Loaded value ' + loadCount;
        }
    }

    public class TestAggregator implements LargeDataProcessor.DataAggregator {
        public Integer total = 0;

        public void initialize() {
            total = 0;
        }

        public void aggregateChunk(List<SObject> records) {
            total += records.size();
        }

        public Object getResult() {
            return total;
        }
    }

    public class TestTransformer implements LargeDataProcessor.RecordTransformer {
        public Object transform(SObject record) {
            return record.get('Name');
        }
    }
}
