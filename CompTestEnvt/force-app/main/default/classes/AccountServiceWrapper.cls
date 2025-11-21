/**
 * @description Wrapper class for paginated Account query responses with heap management
 * @author Development Team
 * @date 2025-11-20
 * @jira [SF-1] - Implement heap-optimized account pagination
 * @group Account Management
 */
public with sharing class AccountServiceWrapper {

    /**
     * @description Time when the query was executed (milliseconds)
     * @jira [SF-1] - Track query execution time
     */
    @AuraEnabled public Long lastQueryTime {get; set;}

    /**
     * @description List of Account records returned from query
     * @jira [SF-1] - Store paginated account results
     */
    @AuraEnabled public List<Account> accountList {get; set;}

    /**
     * @description Indicates if more records exist beyond current page
     * @jira [SF-1] - Support pagination continuation
     */
    @AuraEnabled public Boolean hasMore {get; set;}

    /**
     * @description Flag to stop further queries due to heap limits
     * @jira [SF-1] - Prevent heap limit exceptions
     */
    @AuraEnabled public Boolean shouldStop {get; set;}

    /**
     * @description Offset for next query iteration
     * @jira [SF-1] - Track pagination position
     */
    @AuraEnabled public Integer nextOffset {get; set;}

    /**
     * @description Error message if query fails
     * @jira [SF-1] - Provide error feedback
     */
    @AuraEnabled public String error {get; set;}

    /**
     * @description Constructor initializes wrapper with default values
     * @jira [SF-1] - Initialize wrapper safely
     */
    public AccountServiceWrapper() {
        this.accountList = new List<Account>();
        this.hasMore = false;
        this.shouldStop = false;
        this.nextOffset = 0;
    }
}
