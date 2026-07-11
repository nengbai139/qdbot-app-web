package client

import "context"

// GroupsResponse 群列表
type GroupsResponse struct {
	Groups []GroupSummary `json:"groups"`
	Count  int            `json:"count,omitempty"`
}

// GroupSummary 群摘要
type GroupSummary struct {
	GroupID     string `json:"groupId"`
	GroupName   string `json:"groupName"`
	Name        string `json:"name,omitempty"`
	LastMsg     string `json:"lastMsg,omitempty"`
	UnreadCount int    `json:"unreadCount,omitempty"`
}

// GroupNoticeResponse 群公告
type GroupNoticeResponse struct {
	Notice string `json:"notice"`
}

// InviteMembersResponse 邀请成员结果
type InviteMembersResponse struct {
	Result struct {
		Added   []string `json:"added"`
		Skipped []string `json:"skipped"`
		Failed  []string `json:"failed"`
	} `json:"result"`
}

// GetGroups 获取群列表
func (c *APIClient) GetGroups(ctx context.Context) (*GroupsResponse, error) {
	var resp GroupsResponse
	err := c.do(ctx, "GET", "/app/im/groups", nil, &resp)
	return &resp, err
}

// SendGroupIM 发送群消息
func (c *APIClient) SendGroupIM(ctx context.Context, groupID, content, contentType string) (*SendIMResponse, error) {
	return c.SendIM(ctx, &SendIMRequest{
		GroupID:     groupID,
		Content:     content,
		ContentType: contentType,
	})
}

// GetGroupNotice 获取群公告
func (c *APIClient) GetGroupNotice(ctx context.Context, groupID string) (*GroupNoticeResponse, error) {
	var resp GroupNoticeResponse
	err := c.do(ctx, "GET", "/app/im/group/"+groupID+"/notice", nil, &resp)
	return &resp, err
}

// UpdateGroupNotice 更新群公告
func (c *APIClient) UpdateGroupNotice(ctx context.Context, groupID, notice string) error {
	return c.do(ctx, "PUT", "/app/im/group/"+groupID+"/notice", map[string]string{"notice": notice}, nil)
}

// RevokeMessage 撤回消息
func (c *APIClient) RevokeMessage(ctx context.Context, msgID string) error {
	return c.do(ctx, "POST", "/app/im/revoke/"+msgID, nil, nil)
}

// TransferGroupOwner 转让群主
func (c *APIClient) TransferGroupOwner(ctx context.Context, groupID, newOwnerID string) error {
	return c.do(ctx, "PUT", "/app/im/group/"+groupID+"/transfer", map[string]string{"newOwnerId": newOwnerID}, nil)
}

// InviteGroupMembers 邀请成员
func (c *APIClient) InviteGroupMembers(ctx context.Context, groupID string, members []string) (*InviteMembersResponse, error) {
	var resp InviteMembersResponse
	err := c.do(ctx, "POST", "/app/im/group/"+groupID+"/invite", map[string][]string{"members": members}, &resp)
	return &resp, err
}

// RenameGroup 修改群名称
func (c *APIClient) RenameGroup(ctx context.Context, groupID, name string) error {
	return c.do(ctx, "PUT", "/app/im/group/"+groupID+"/name", map[string]string{"name": name}, nil)
}

// SetGroupMemberAlias 设置成员备注
func (c *APIClient) SetGroupMemberAlias(ctx context.Context, groupID, userID, alias string) error {
	return c.do(ctx, "PUT", "/app/im/group/"+groupID+"/member/"+userID+"/alias", map[string]string{"alias": alias}, nil)
}

// RemoveGroupMember 移除群成员（群主操作）
func (c *APIClient) RemoveGroupMember(ctx context.Context, groupID, userID string) error {
	return c.do(ctx, "POST", "/app/im/group/"+groupID+"/leave", map[string]string{"userId": userID}, nil)
}
