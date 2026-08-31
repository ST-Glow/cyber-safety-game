class_name DataRepairPairs
extends RefCounted


const ITEMS: Array[Dictionary] = [
	{"id":"m01","area_id":"area_1","problem":"搜索结果有醒目标题","problem_short":"醒目搜索结果","problem_icon":"search_alert","solution":"检查作者、日期与原始来源后再采用","solution_short":"核验来源","solution_icon":"verify_source","decoy":"立刻转发标题最醒目的结果","hint":"标题是否醒目，不能代替对作者、日期和来源的核验。","accent":"49c8ff"},
	{"id":"m02","area_id":"area_1","problem":"两篇文章结论冲突","problem_short":"结论冲突","problem_icon":"conflict_docs","solution":"比较证据质量并交叉核验","solution_short":"交叉核验","solution_icon":"cross_check","decoy":"只保留符合自己观点的一篇","hint":"结论冲突时，应比较双方证据，而不是只选自己认同的观点。","accent":"6aabff"},
	{"id":"m03","area_id":"area_1","problem":"资料太多难以查找","problem_short":"资料拥堵","problem_icon":"data_stack","solution":"按来源、主题与日期建立标签","solution_short":"分类标签","solution_icon":"organize_tags","decoy":"全部堆在同一个无标题文件夹","hint":"可检索的标签和分类，才能真正解决资料混乱。","accent":"58d6c7"},
	{"id":"m04","area_id":"area_1","problem":"AI给出一个统计数字","problem_short":"AI统计数字","problem_icon":"ai_chart","solution":"追溯数据集与计算口径","solution_short":"追溯数据","solution_icon":"trace_data","decoy":"因为语气肯定就直接使用","hint":"语气肯定不等于数据可靠，需要追溯数据集和计算口径。","accent":"7bb8ff"},
	{"id":"m05","area_id":"area_1","problem":"网页可能已经过期","problem_short":"网页已过期？","problem_icon":"web_clock","solution":"检查更新时间和当前权威信息","solution_short":"检查时效","solution_icon":"current_info","decoy":"忽略日期，只看页面排版","hint":"页面排版不能说明信息仍然有效，应先检查更新时间。","accent":"69d2ff"},
	{"id":"m06","area_id":"area_3","problem":"修改AI生成的海报","problem_short":"编辑AI海报","problem_icon":"edit_image","solution":"保留修改记录并核对素材许可","solution_short":"记录与许可","solution_icon":"license_edit","decoy":"删除所有来源说明","hint":"修改作品时仍需保留过程证据，并核对素材许可。","accent":"b586ff"},
	{"id":"m07","area_id":"area_3","problem":"公开发布AI辅助文章","problem_short":"发布AI文章","problem_icon":"ai_upload","solution":"按要求标注AI参与和素材来源","solution_short":"透明标注","solution_icon":"disclosure","decoy":"宣称全部内容均为原创人工完成","hint":"公开发布时，应透明标注AI参与和素材来源。","accent":"9d8cff"},
	{"id":"m08","area_id":"area_3","problem":"合并图片、文字和数据","problem_short":"多媒体合并","problem_icon":"multimedia","solution":"选择兼容格式并保持可访问性","solution_short":"兼容可访问","solution_icon":"accessible_format","decoy":"只考虑视觉效果，忽略可读性","hint":"多媒体作品不仅要好看，也要兼容并保持可读性。","accent":"7c96ff"},
	{"id":"m09","area_id":"area_3","problem":"复用网络图片","problem_short":"复用网络图片","problem_icon":"network_image","solution":"核对版权许可并正确署名","solution_short":"版权署名","solution_icon":"copyright","decoy":"能下载就代表可以任意使用","hint":"能够下载不代表拥有使用权，应核对许可并署名。","accent":"c47dff"},
	{"id":"m10","area_id":"area_3","problem":"迭代数字作品","problem_short":"作品迭代","problem_icon":"version_loop","solution":"根据反馈修改并保存版本","solution_short":"保存版本","solution_icon":"versioning","decoy":"覆盖原文件且不记录变更","hint":"迭代需要保留版本，才能追踪反馈和修改。","accent":"8e83ff"},
]


static func all_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in ITEMS:
		result.append(item.duplicate(true))
	return result


static func item_by_id(item_id: String) -> Dictionary:
	for item in ITEMS:
		if String(item.get("id", "")) == item_id:
			return item.duplicate(true)
	return {}
