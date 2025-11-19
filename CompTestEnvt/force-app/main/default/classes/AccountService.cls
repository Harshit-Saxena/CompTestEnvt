/**
 * @description Improved AccountService with advanced heap management
 * @author CompTestEnvt Team
 * @date 2024
 */
public with sharing class AccountService {

    // Service response wrapper
    public class AccountServiceResponse {
        @AuraEnabled public List<Account> accounts {get; set;}
        @AuraEnabled public Integer totalCount {get; set;}
        @AuraEnabled public Integer currentOffset {get; set;}
        @AuraEnabled public Integer pageSize {get; set;}
        @AuraEnabled public Boolean hasMore {get; set;}
        @AuraEnabled public Boolean hasPrevious {get; set;}
        @AuraEnabled public HeapSizeManager.HeapStats heapStats {get; set;}
        @AuraEnabled public Long queryTime {get; set;}
        @AuraEnabled public String status {get; set;} // SUCCESS, WARNING, ERROR
        @AuraEnabled public String message {get; set;}

        public AccountServiceResponse() {
            this.accounts = new List<Account>();
            this.status = 'SUCCESS';
            this.currentOffset = 0;
        }
    }

    // Constants
    private static final Integer DEFAULT_PAGE_SIZE = 100;
    private static final Integer MAX_PAGE_SIZE = 2000;
    private static final Integer INITIAL_LOAD_SIZE = 50;

    /**
     * @description Get accounts with intelligent pagination and heap management
     * @param pageNumber Current page number (1-based)
     * @param pageSize Records per page
     * @param filterType Optional filter (Customer, Prospect, Partner, etc.)
     * @param searchTerm Optional search term for name
     * @return AccountServiceResponse with accounts and metadata
     */
    @AuraEnabled(cacheable=true)
    public static AccountServiceResponse getAccounts(
        Integer pageNumber,
        Integer pageSize,
        String filterType,
        String searchTerm
    ) {
        AccountServiceResponse response = new AccountServiceResponse();
        Long startTime = System.currentTimeMillis();

        try {
            // Validate and adjust parameters
            pageNumber = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
            pageSize = (pageSize == null || pageSize < 1) ? DEFAULT_PAGE_SIZE : pageSize;
            pageSize = Math.min(pageSize, MAX_PAGE_SIZE);

            // Check heap before processing
            response.heapStats = HeapSizeManager.getCurrentHeapStats();

            if (response.heapStats.status == 'CRITICAL') {
                response.status = 'ERROR';
                response.message = 'Insufficient memory to process request. Please reduce page size.';
                return response;
            }

            // Adjust page size based on heap
            if (response.heapStats.status == 'WARNING') {
                pageSize = Math.min(pageSize, response.heapStats.recommendedBatchSize);
                response.status = 'WARNING';
                response.message = 'Page size adjusted to ' + pageSize + ' due to memory constraints.';
            }

            // Build dynamic query
            String query = buildAccountQuery(filterType, searchTerm);

            // Get paginated results
            LargeDataProcessor.PaginatedResult result =
                LargeDataProcessor.getPaginatedRecords(query, pageNumber, pageSize);

            // Map results to response
            response.accounts = (List<Account>)result.records;
            response.totalCount = result.totalRecords;
            response.currentOffset = result.currentOffset;
            response.pageSize = result.pageSize;
            response.hasMore = result.hasNext;
            response.hasPrevious = result.hasPrevious;
            response.heapStats = result.heapStats;

            // Optimize memory if needed
            if (response.heapStats.status == 'WARNING' && response.accounts.size() > 100) {
                optimizeAccountList(response.accounts);
            }

        } catch (Exception e) {
            response.status = 'ERROR';
            response.message = 'Failed to retrieve accounts: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'AccountService.getAccounts error: ' + e.getStackTraceString());
        }

        response.queryTime = System.currentTimeMillis() - startTime;
        return response;
    }

    /**
     * @description Get accounts using streaming for large datasets
     * @param batchSize Size of each batch
     * @param maxRecords Maximum records to retrieve
     * @return List of AccountServiceResponse batches
     */
    @AuraEnabled
    public static List<AccountServiceResponse> getAccountsInBatches(
        Integer batchSize,
        Integer maxRecords
    ) {
        List<AccountServiceResponse> responses = new List<AccountServiceResponse>();
        batchSize = (batchSize == null) ? DEFAULT_PAGE_SIZE : batchSize;
        maxRecords = (maxRecords == null) ? 10000 : maxRecords;

        try {
            String query = 'SELECT Id, Name, Phone, Type, Industry, BillingCity, ' +
                          'BillingState, AnnualRevenue, NumberOfEmployees ' +
                          'FROM Account ORDER BY CreatedDate DESC';

            LargeDataProcessor.DataStream stream =
                new LargeDataProcessor.DataStream(query, batchSize);

            Integer totalProcessed = 0;

            while (stream.hasNext() && totalProcessed < maxRecords) {
                AccountServiceResponse response = new AccountServiceResponse();
                response.accounts = (List<Account>)stream.next();

                if (response.accounts.isEmpty()) {
                    break;
                }

                response.currentOffset = stream.getOffset();
                response.pageSize = response.accounts.size();
                response.heapStats = stream.getLastHeapStats();
                response.hasMore = stream.hasNext();

                responses.add(response);
                totalProcessed += response.accounts.size();

                // Break if heap is critical
                if (response.heapStats.status == 'CRITICAL') {
                    response.status = 'WARNING';
                    response.message = 'Stopped due to memory constraints';
                    break;
                }
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Batch processing failed: ' + e.getMessage());
        }

        return responses;
    }

    /**
     * @description Process large account updates efficiently
     * @param accountIds List of account IDs to update
     * @param fieldUpdates Map of field names to values
     * @return Boolean success status
     */
    @AuraEnabled
    public static Boolean updateAccountsEfficiently(
        List<Id> accountIds,
        Map<String, Object> fieldUpdates
    ) {
        if (accountIds == null || accountIds.isEmpty() || fieldUpdates == null) {
            return false;
        }

        try {
            // Process in chunks to avoid heap issues
            List<List<Object>> idChunks = MemoryOptimizer.splitIntoChunks(
                new List<Object>(accountIds), 200
            );

            for (List<Object> chunk : idChunks) {
                // Check heap before processing chunk
                if (!HeapSizeManager.monitorHeap('Account update chunk')) {
                    throw new HeapException('Insufficient heap for update operation');
                }

                List<Id> chunkIds = new List<Id>();
                for (Object obj : chunk) {
                    chunkIds.add((Id)obj);
                }

                // Query and update accounts
                List<Account> accounts = [
                    SELECT Id FROM Account
                    WHERE Id IN :chunkIds
                ];

                for (Account acc : accounts) {
                    for (String field : fieldUpdates.keySet()) {
                        acc.put(field, fieldUpdates.get(field));
                    }
                }

                update accounts;

                // Clear memory
                accounts.clear();
            }

            return true;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Update failed: ' + e.getMessage());
            return false;
        }
    }

    /**
     * @description Get account statistics with memory optimization
     * @return Map of statistics
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAccountStatistics() {
        Map<String, Object> stats = new Map<String, Object>();

        try {
            // Use aggregation for efficiency
            stats.put('totalAccounts', [SELECT COUNT() FROM Account]);

            // Get type distribution
            List<AggregateResult> typeResults = [
                SELECT Type, COUNT(Id) cnt
                FROM Account
                WHERE Type != null
                GROUP BY Type
                LIMIT 10
            ];

            Map<String, Integer> typeDistribution = new Map<String, Integer>();
            for (AggregateResult ar : typeResults) {
                typeDistribution.put(
                    (String)ar.get('Type'),
                    (Integer)ar.get('cnt')
                );
            }
            stats.put('typeDistribution', typeDistribution);

            // Get industry distribution
            List<AggregateResult> industryResults = [
                SELECT Industry, COUNT(Id) cnt
                FROM Account
                WHERE Industry != null
                GROUP BY Industry
                LIMIT 10
            ];

            Map<String, Integer> industryDistribution = new Map<String, Integer>();
            for (AggregateResult ar : industryResults) {
                industryDistribution.put(
                    (String)ar.get('Industry'),
                    (Integer)ar.get('cnt')
                );
            }
            stats.put('industryDistribution', industryDistribution);

            // Add heap information
            HeapSizeManager.HeapStats heapStats = HeapSizeManager.getCurrentHeapStats();
            stats.put('memoryUsage', heapStats.heapUsagePercent);
            stats.put('memoryStatus', heapStats.status);

        } catch (Exception e) {
            stats.put('error', e.getMessage());
        }

        return stats;
    }

    /**
     * @description Build dynamic SOQL query for accounts
     */
    private static String buildAccountQuery(String filterType, String searchTerm) {
        String query = 'SELECT Id, Name, Phone, Type, Industry, BillingCity, ' +
                      'BillingState, AnnualRevenue, NumberOfEmployees, CreatedDate ' +
                      'FROM Account';

        List<String> conditions = new List<String>();

        if (String.isNotBlank(filterType)) {
            conditions.add('Type = \'' + String.escapeSingleQuotes(filterType) + '\'');
        }

        if (String.isNotBlank(searchTerm)) {
            conditions.add('Name LIKE \'%' + String.escapeSingleQuotes(searchTerm) + '%\'');
        }

        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }

        query += ' ORDER BY CreatedDate DESC';

        return query;
    }

    /**
     * @description Optimize account list for memory efficiency
     */
    private static void optimizeAccountList(List<Account> accounts) {
        // Keep only essential fields for large lists
        Set<String> essentialFields = new Set<String>{
            'Id', 'Name', 'Type', 'Phone', 'BillingCity'
        };

        MemoryOptimizer.optimizeSObjectList(accounts, essentialFields);
    }

    /**
     * @description Custom exception for heap issues
     */
    public class HeapException extends Exception {}
}